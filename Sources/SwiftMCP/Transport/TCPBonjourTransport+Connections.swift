#if Server
import Foundation
import Logging

#if canImport(Network)
import Network

extension TCPBonjourTransport {
    // MARK: - Connections

    internal func handleNewConnection(_ connection: NWConnection) {
        let connectionID = UUID()

        Task {
            // One session per TCP connection; `SessionManager` attaches this
            // transport so outbound bytes route back over the same socket.
            let session = await sessionManager.session(id: connectionID)

            connection.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    self.logger.info("TCP connection ready: \(connectionID)")
                case .failed(let error):
                    self.logger.error("TCP connection failed (\(connectionID)): \(error)")
                    Task {
                        await self.cleanupConnection(id: connectionID)
                    }
                case .cancelled:
                    Task {
                        await self.cleanupConnection(id: connectionID)
                    }
                default:
                    break
                }
            }

            await state.addConnection(id: connectionID, connection: connection)
            connection.start(queue: queue)
            startReceiveLoop(connection: connection, session: session, connectionID: connectionID)
        }
    }

    internal func cleanupConnection(id: UUID) async {
        await state.removeConnection(id: id)
        await sessionManager.removeSession(id: id)
    }

    internal func startReceiveLoop(connection: NWConnection, session: Session, connectionID: UUID) {
        let lineBuffer = LineBuffer()
        receiveNext(connection: connection, session: session, connectionID: connectionID, lineBuffer: lineBuffer)
    }

    internal func receiveNext(
        connection: NWConnection,
        session: Session,
        connectionID: UUID,
        lineBuffer: LineBuffer
    ) {
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: 64 * 1024
        ) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let data, !data.isEmpty {
                Task {
                    await lineBuffer.append(data)
                    let lines = await lineBuffer.processLines()
                    for line in lines {
                        await self.handleLine(line, session: session)
                    }
                }
            }

            if let error {
                self.logger.error("TCP receive error (\(connectionID)): \(error)")
                Task {
                    await self.cleanupConnection(id: connectionID)
                }
                return
            }

            if isComplete {
                Task {
                    if let remaining = await lineBuffer.getRemaining() {
                        await self.handleLine(remaining, session: session)
                    }
                    await self.cleanupConnection(id: connectionID)
                }
                return
            }

            self.receiveNext(
                connection: connection,
                session: session,
                connectionID: connectionID,
                lineBuffer: lineBuffer
            )
        }
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
