#if Server
import Foundation
import Logging

#if canImport(Network)
import Network

extension TCPBonjourTransport {
    // MARK: - Connections

    internal func handleNewConnection(_ connection: NWConnection) {
        let connectionID = UUID()
        let tracker = ConnectionTaskTracker()

        // Installed before the first suspension: a connection that fails while
        // its session is still being created must already have a cleanup path.
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.logger.info("TCP connection ready: \(connectionID)")
            case .failed(let error):
                self.logger.error("TCP connection failed (\(connectionID)): \(error)")
                Task {
                    await self.cleanupConnection(id: connectionID)
                    await self.escalateIfDescriptorExhaustion(error)
                }
            case .cancelled:
                Task {
                    await self.cleanupConnection(id: connectionID)
                }
            default:
                break
            }
        }

        Task {
            // One session per TCP connection; `SessionManager` attaches this
            // transport so outbound bytes route back over the same socket.
            let session = await sessionManager.session(id: connectionID)

            guard await state.addConnection(id: connectionID, connection: connection, tasks: tracker) else {
                // The transport stopped while this connection was being set up.
                // Every early return on this path must cancel: the kernel already
                // allocated the descriptor at accept, and only `cancel()` frees it.
                connection.cancel()
                await sessionManager.removeSession(id: connectionID)
                return
            }
            connection.start(queue: queue)
            startReceiveLoop(
                connection: connection, session: session,
                connectionID: connectionID, tracker: tracker
            )
        }
    }

    internal func cleanupConnection(id: UUID) async {
        // `removeConnection` cancels the `NWConnection` (releasing its socket)
        // and every in-flight dispatch task for this connection.
        await state.removeConnection(id: id)
        await sessionManager.removeSession(id: id)
    }

    internal func startReceiveLoop(
        connection: NWConnection,
        session: Session,
        connectionID: UUID,
        tracker: ConnectionTaskTracker
    ) {
        let framer = LineFramer()
        receiveNext(
            connection: connection, session: session,
            connectionID: connectionID, framer: framer, tracker: tracker
        )
    }

    internal func receiveNext(
        connection: NWConnection,
        session: Session,
        connectionID: UUID,
        framer: LineFramer,
        tracker: ConnectionTaskTracker
    ) {
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: 64 * 1024
        ) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            // Line assembly happens synchronously on the connection's serial
            // queue: receive callbacks arrive in order here, whereas hopping
            // each chunk into a task would let two chunks interleave mid-line.
            // Only the dispatch of complete lines leaves the queue.
            var lines: [String] = []
            if let data, !data.isEmpty {
                framer.append(data)
                lines = framer.extractLines()
            }

            if let error {
                self.logger.error("TCP receive error (\(connectionID)): \(error)")
                self.dispatchLines(lines, session: session, tracker: tracker)
                Task {
                    await self.cleanupConnection(id: connectionID)
                }
                return
            }

            if isComplete {
                // All appends happened on this queue, so the final unterminated
                // line is complete here — flushing from a racing task could run
                // before the data callback and silently drop it.
                if let remaining = framer.remainder() {
                    lines.append(remaining)
                }
                // The final lines dispatch tracked like every other batch — a
                // one-shot client delivers request and FIN in the same read,
                // and an untracked handler here would be unreapable: a hung
                // tool would block cleanup forever with nothing able to cancel
                // it. The drain below bounds it exactly like earlier handlers.
                self.dispatchLines(lines, session: session, tracker: tracker)
                // A clean EOF is a half-close, not an abort: the peer may keep
                // its read side open for replies still being computed. Let the
                // tracked handlers drain (bounded) before the socket is torn
                // down; cleanup's cancel reaps whatever outlived the timeout.
                // Untracked on purpose: this task waits on the tracked ones,
                // so tracking it would have it wait on itself.
                let drainTimeout = self.eofDrainTimeout
                Task {
                    await tracker.drain(timeout: drainTimeout)
                    await self.cleanupConnection(id: connectionID)
                }
                return
            }

            self.dispatchLines(lines, session: session, tracker: tracker)
            self.receiveNext(
                connection: connection,
                session: session,
                connectionID: connectionID,
                framer: framer,
                tracker: tracker
            )
        }
    }

    /// Dispatches already-extracted lines on a task tracked by the connection,
    /// so teardown can cancel whatever they started.
    ///
    /// Cancellation notifications go first: coalesced into the same read as
    /// the request they name (one client flush, Nagle, a single 64 KB read),
    /// they would otherwise wait in this sequential loop behind that request's
    /// completion and cancel nothing. Handled first, the session retains them
    /// until the request registers and cancels it on the spot.
    private func dispatchLines(_ lines: [String], session: Session, tracker: ConnectionTaskTracker) {
        guard !lines.isEmpty else { return }
        tracker.spawn {
            let (cancellations, rest) = Self.partitionCancellations(lines)
            for line in cancellations {
                await self.handleLine(line, session: session)
            }
            for line in rest {
                await self.handleLine(line, session: session)
            }
        }
    }

    /// Splits out `notifications/cancelled` lines, preserving relative order
    /// within each partition. The substring test is only a cheap pre-filter;
    /// a line moves only when it actually decodes to that lone notification.
    internal static func partitionCancellations(
        _ lines: [String]
    ) -> (cancellations: [String], rest: [String]) {
        var cancellations: [String] = []
        var rest: [String] = []
        for line in lines {
            if line.contains("notifications/cancelled"),
               let data = line.data(using: .utf8),
               let messages = try? JSONRPCMessage.decodeMessages(from: data),
               messages.count == 1,
               case .notification(let notification) = messages[0],
               notification.method == "notifications/cancelled" {
                cancellations.append(line)
            } else {
                rest.append(line)
            }
        }
        return (cancellations, rest)
    }

    /// Escalates descriptor exhaustion to a terminal transport failure.
    ///
    /// Out of descriptors, this process cannot accept anything anymore — and the
    /// listener itself reports nothing in that state (it stays `.ready` and
    /// silently stops accepting), so the failure must be caught wherever it does
    /// surface. Failing terminally makes `run()` throw, so a supervised daemon
    /// exits and gets restarted instead of serving nothing forever.
    internal func escalateIfDescriptorExhaustion(_ error: NWError) async {
        guard Self.isDescriptorExhaustion(error) else { return }
        logger.critical("Out of file descriptors (\(error)); failing the TCP+Bonjour transport terminally.")
        await state.failTerminally(TransportError.resourceExhausted(
            "The process is out of file descriptors; the TCP+Bonjour transport cannot accept connections."
        ))
    }

    /// `true` for POSIX `EMFILE` (per-process) / `ENFILE` (system-wide)
    /// descriptor-table exhaustion.
    internal static func isDescriptorExhaustion(_ error: NWError) -> Bool {
        if case .posix(let code) = error, code == .EMFILE || code == .ENFILE {
            return true
        }
        return false
    }

    /// Decodes one newline-delimited line and routes it. The session is bound as
    /// `Session.current` for the duration, so a tool's outbound (responses,
    /// notifications, mid-call `sampling`/`elicitation` requests) flows back over
    /// this connection.
    internal func handleLine(_ line: String, session: Session) async {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = line.data(using: .utf8) else {
            return
        }

        logger.trace("TCP IN:\n\n\(line)")

        await session.work { _ in
            do {
                let messages = try JSONRPCMessage.decodeMessages(from: data)
                if let dispatcher = self.dispatcher {
                    try await self.dispatch(messages, through: dispatcher)
                } else {
                    try await self.dispatchCoupled(messages, data: data, session: session)
                }
            } catch {
                self.logger.error("Error decoding TCP message: \(error)")
            }
        }
    }

    /// Decoupled dispatch: the gate and dispatch live behind the
    /// ``MCPDispatcher``. Calls `handle` for a single message or a batch, then
    /// writes any reply back over the socket.
    private func dispatch(_ messages: [JSONRPCMessage], through dispatcher: any MCPDispatcher) async throws {
        let replies: [JSONRPCMessage]
        if messages.count == 1 {
            if let reply = await dispatcher.handle(messages[0]) {
                replies = [reply]
            } else {
                replies = []
            }
        } else {
            replies = await dispatcher.handle(messages)
        }
        guard !replies.isEmpty else { return }
        try await send(replies)
    }

    /// Server-coupled dispatch: apply the inline gate, then process through the
    /// transport's own server.
    private func dispatchCoupled(_ messages: [JSONRPCMessage], data: Data, session: Session) async throws {
        if await SessionInitializationGate.shouldReject(messages, for: session) {
            logger.warning("Rejected TCP request before initialize (\(session.id))")
            let rejections = SessionInitializationGate.rejectionResponses(for: messages)
            if !rejections.isEmpty {
                try await send(rejections)
            }
            return
        }

        let batchVersion = await JSONRPCMessage.batchingVersion(for: messages, session: session)
        if JSONRPCMessage.batchingRejected(body: data, version: batchVersion) {
            logger.warning("Rejected TCP batch on protocol version \(batchVersion) (\(session.id))")
            try await send([JSONRPCMessage.batchingRejectionResponse(version: batchVersion)])
            return
        }

        guard let server = self.server else { return }
        let responses = await server.processBatch(messages)
        guard !responses.isEmpty else { return }
        try await send(responses)
    }
}
#endif
#endif
