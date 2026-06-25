#if Server
import Foundation

#if canImport(Network)
import Network

extension TCPBonjourTransport {
    // MARK: - Listener Creation

    /// Creates a new NWListener with the transport's configuration.
    internal func createListener() throws -> NWListener {
        let parameters = NWParameters.tcp
        parameters.acceptLocalOnly = acceptLocalOnly
        parameters.includePeerToPeer = false
        if preferIPv4,
           let ipOptions = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            ipOptions.version = .v4
        }

        let listener: NWListener
        if let port {
            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                throw TransportError.bindingFailed("Invalid TCP port: \(port)")
            }
            listener = try NWListener(using: parameters, on: nwPort)
        } else {
            listener = try NWListener(using: parameters)
        }

        // In the connection-based mode `serviceName` is always provided; in the
        // server-coupled mode it falls back to the server's name.
        let advertisedName = serviceName ?? server?.serverName ?? "MCP"
        listener.service = NWListener.Service(name: advertisedName, type: serviceType, domain: serviceDomain)
        listener.newConnectionHandler = { [weak self] connection in
            self?.handleNewConnection(connection)
        }

        return listener
    }

    /// Installs a state handler on a listener that captures only the generation token,
    /// avoiding a strong reference to the listener itself.
    internal func installStateHandler(on listener: NWListener, generation: UInt64) {
        listener.stateUpdateHandler = { [weak self] newState in
            guard let self else { return }
            Task {
                await self.handleListenerState(newState, generation: generation)
            }
        }
    }

    // MARK: - Listener State Handling

    internal func handleListenerState(_ newState: NWListener.State, generation: UInt64) async {
        switch newState {
        case .ready:
            if let boundPort = await state.listenerReady(generation: generation) {
                port = boundPort
            }
            logger.info("TCP+Bonjour transport ready on port \(port.map(String.init) ?? "unknown")")

        case .failed(let error):
            if Self.isRetryableError(error) {
                guard let delay = await state.listenerFailed(generation: generation) else {
                    return  // stopped or stale generation
                }
                logger.warning("Bonjour listener failed (mDNSResponder unavailable): \(error). Retrying in \(delay)s.")
                scheduleRetry(afterDelay: delay, failedGeneration: generation)
            } else {
                logger.error("TCP+Bonjour listener failed: \(error)")
            }

        case .cancelled:
            logger.info("TCP+Bonjour listener cancelled")

        default:
            break
        }
    }

    /// Returns `true` when the error indicates the mDNS daemon is unavailable
    /// (DNS service error -65563 / `kDNSServiceErr_ServiceNotRunning`).
    internal static func isRetryableError(_ error: NWError) -> Bool {
        if case .dns(let dnsError) = error, dnsError == -65563 {
            return true
        }
        return false
    }

    // MARK: - Retry

    /// Schedules a single retry attempt after the given delay.
    /// The retry task is tracked in state and can be cancelled by `stop()`.
    internal func scheduleRetry(afterDelay delay: UInt64, failedGeneration: UInt64) {
        let task = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: delay * 1_000_000_000)
            } catch {
                return  // cancelled
            }

            guard let self else { return }

            do {
                let newListener = try self.createListener()
                guard let newGeneration = await self.state.replaceListener(
                    newListener,
                    expectedGeneration: failedGeneration
                ) else {
                    // Transport was stopped or generation changed — discard
                    newListener.cancel()
                    return
                }
                self.installStateHandler(on: newListener, generation: newGeneration)
                newListener.start(queue: self.queue)
                self.logger.info("Bonjour listener re-created after retry, waiting for it to become ready.")
            } catch {
                // createListener() itself failed — schedule another retry
                // with the same generation (state.listenerFailed already incremented attempt)
                guard let nextDelay = await self.state.listenerFailed(generation: failedGeneration) else {
                    return
                }
                self.logger.warning("Bonjour listener retry failed: \(error). Retrying in \(nextDelay)s.")
                self.scheduleRetry(afterDelay: nextDelay, failedGeneration: failedGeneration)
            }
        }

        Task {
            await state.setRetryTask(task)
        }
    }
}
#endif
#endif
