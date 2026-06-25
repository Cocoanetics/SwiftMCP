#if Server
import Foundation
import Logging

#if canImport(Network)
import Network

extension TCPBonjourTransport {
    // MARK: - Connections

    internal func handleNewConnection(_ connection: NWConnection) {
        // Connection-based mode: surface the TCP connection as an `MCPConnection`
        // and let `serve(over:)` route it.
        if server == nil {
            handleNewConnectionAsChannel(connection)
            return
        }

        let connectionID = UUID()

        Task {
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
            } catch {
                logger.error("Error decoding TCP message: \(error)")
            }
        }
    }

    // MARK: - Connection-based mode

    /// Accepts a TCP connection in the connection-based mode: wraps it as an
    /// ``MCPConnection``, yields it to ``TCPBonjourTransport/connections``, and
    /// feeds decoded frames to its `inbound` stream. Dispatch is `serve`'s job.
    internal func handleNewConnectionAsChannel(_ connection: NWConnection) {
        let connectionID = UUID()
        let channel = NWConnectionChannel(connection: connection, logger: logger)
        connectionsContinuation.yield(channel)

        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.logger.info("TCP connection ready: \(connectionID)")
            case .failed(let error):
                self.logger.error("TCP connection failed (\(connectionID)): \(error)")
                channel.close()
                Task { await self.state.removeConnection(id: connectionID) }
            case .cancelled:
                channel.close()
                Task { await self.state.removeConnection(id: connectionID) }
            default:
                break
            }
        }

        Task { await state.addConnection(id: connectionID, connection: connection) }
        connection.start(queue: queue)
        receiveNextChannel(
            connection: connection,
            channel: channel,
            connectionID: connectionID,
            lineBuffer: LineBuffer()
        )
    }

    private func receiveNextChannel(
        connection: NWConnection,
        channel: NWConnectionChannel,
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
                        self.deliver(line, to: channel)
                    }
                }
            }

            if let error {
                self.logger.error("TCP receive error (\(connectionID)): \(error)")
                channel.close()
                Task { await self.state.removeConnection(id: connectionID) }
                return
            }

            if isComplete {
                Task {
                    if let remaining = await lineBuffer.getRemaining() {
                        self.deliver(remaining, to: channel)
                    }
                    channel.close()
                    await self.state.removeConnection(id: connectionID)
                }
                return
            }

            self.receiveNextChannel(
                connection: connection,
                channel: channel,
                connectionID: connectionID,
                lineBuffer: lineBuffer
            )
        }
    }

    /// Decodes a single newline-delimited line into a JSON-RPC frame and
    /// forwards it to the connection's `inbound` stream.
    private func deliver(_ line: String, to channel: NWConnectionChannel) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = line.data(using: .utf8) else { return }

        logger.trace("TCP IN:\n\n\(line)")
        do {
            let messages = try JSONRPCMessage.decodeMessages(from: data)
            channel.deliver(messages)
        } catch {
            logger.error("Error decoding TCP message: \(error)")
        }
    }
}

/// An ``MCPConnection`` backed by a single `NWConnection`. It owns a fresh
/// session; inbound frames (a TCP line decodes to one frame) are pushed in by the
/// transport's receive loop; `send` encodes a frame and writes it to the socket
/// as one newline-delimited payload. Bespoke (rather than ``BasicConnection``)
/// because it has to hold the non-`Sendable` `NWConnection`.
private final class NWConnectionChannel: MCPConnection, @unchecked Sendable {
    let session = Session(id: UUID())
    let inbound: AsyncStream<MCPInboundFrame>
    private let inboundContinuation: AsyncStream<MCPInboundFrame>.Continuation
    private let connection: NWConnection
    private let logger: Logger

    init(connection: NWConnection, logger: Logger) {
        self.connection = connection
        self.logger = logger
        var continuation: AsyncStream<MCPInboundFrame>.Continuation!
        inbound = AsyncStream { continuation = $0 }
        inboundContinuation = continuation
    }

    func deliver(_ messages: [JSONRPCMessage]) {
        inboundContinuation.yield(MCPInboundFrame(messages))
    }

    func close() {
        inboundContinuation.finish()
    }

    func send(_ frame: [JSONRPCMessage]) async throws {
        let data = try JSONRPCFrame.encode(frame)
        logger.trace("TCP OUT:\n\n\(String(data: data, encoding: .utf8) ?? "")")
        var out = data
        out.append(Data("\n".utf8))

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: out, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }
}
#endif
#endif
