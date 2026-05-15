import Foundation

extension HTTPSSETransport {
    /// Start the keep-alive timer that sends messages every 60 seconds.
    internal func startKeepAliveTimer() {
        keepAliveTimer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
        keepAliveTimer?.schedule(deadline: .now(), repeating: .seconds(60))
        keepAliveTimer?.setEventHandler { [weak self] in
            self?.sendKeepAlive()
        }
        keepAliveTimer?.resume()
        logger.trace("Started keep-alive timer")
    }

    /// Stop the keep-alive timer.
    internal func stopKeepAliveTimer() {
        keepAliveTimer?.cancel()
        keepAliveTimer = nil
        logger.trace("Stopped keep-alive timer")
    }

    /// Send a keep-alive message to all connected SSE clients.
    internal func sendKeepAlive() {
        Task { [weak self] in
            guard let self = self else { return }

            switch self.keepAliveMode {
            case .none:
                return
            case .sse:
                let activeStreamIDs = await self.sessionManager.activeStreamIDs()
                for streamID in activeStreamIDs {
                    _ = await self.sessionManager.sendComment("keep-alive", to: streamID)
                }
            case .ping:
                await self.sessionManager.forEachSession { session in
                    guard await self.sessionManager.hasActivePrimaryGeneralConnection(for: session.id) else {
                        return
                    }

                    Task {
                        let ping = JSONRPCMessage.request(id: .string(UUID().uuidString), method: "ping")
                        do {
                            try await session.send(ping)
                        } catch {
                            print("Failed to send ping to session \(session.id): \(error)")
                        }
                    }
                }
            }
        }
    }
}
