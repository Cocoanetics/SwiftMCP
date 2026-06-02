#if Server
import Foundation

#if canImport(Network)
import Network

extension TCPBonjourTransport {
    // MARK: - Connections

    internal func handleNewConnection(_ connection: NWConnection) {
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
                    try await send(SessionInitializationGate.rejectionResponses(for: messages))
                    return
                }

                let responses = await server.processBatch(messages)
                guard !responses.isEmpty else { return }
                try await send(responses)
            } catch {
                logger.error("Error decoding TCP message: \(error)")
            }
        }
    }
}
#endif
#endif
