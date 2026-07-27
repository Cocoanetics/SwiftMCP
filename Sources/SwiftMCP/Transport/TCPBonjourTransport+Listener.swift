#if Server
import Foundation

#if canImport(Network)
import Network

extension TCPBonjourTransport {
    // MARK: - Listener Creation

    /// Creates a new NWListener with the transport's configuration.
    ///
    /// The scope decides both how the socket binds and who advertises:
    ///
    /// - **Local scopes** bind loopback and are advertised by ``LocalOnlyRegistration``,
    ///   because `NWListener.Service` has no interface-scope parameter and would
    ///   publish to the whole link regardless of how the socket is bound. That
    ///   mismatch — serving narrow while advertising wide — is the bug this
    ///   redesign exists to remove.
    /// - **`.localNetwork`** is advertised by `NWListener` itself, with TXT.
    internal func createListener() throws -> NWListener {
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = false
        if scope.isLocalOnly {
            // Not `acceptLocalOnly` — that means the directly attached link, i.e.
            // the LAN, which is exactly the misreading this replaces.
            parameters.requiredInterfaceType = .loopback
        } else {
            // `.localNetwork` means the attached link, so bound the socket to it.
            // Leaving this at its default would accept connections arriving over
            // routed interfaces — wider than what is advertised, and the transport
            // has no authorization hook to make up the difference.
            parameters.acceptLocalOnly = true
        }
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

        if !scope.isLocalOnly {
            listener.service = NWListener.Service(
                name: advertisedInstanceName,
                type: MCPBonjour.serviceType,
                domain: scope.domain,
                txtRecord: NWTXTRecord(txtRecord.entries)
            )
            listener.serviceRegistrationUpdateHandler = { [weak self] change in
                guard case .add(let endpoint) = change,
                      case .service(let name, _, _, _) = endpoint else { return }
                self?.resolvedInstanceName = name
            }
        }

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
                await waitForSiblingHTTPEndpoint()
                await publishLocalService(on: boundPort, generation: generation)
                await republishNetworkService(generation: generation)
            }
            logger.info("""
                TCP+Bonjour transport ready on port \(port.map(String.init) ?? "unknown") \
                as "\(resolvedInstanceName ?? advertisedInstanceName)" (\(scope))
                """)

        case .failed(let error):
            await state.removeLocalRegistration(generation: generation)
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

    /// Gives a sibling HTTP transport a brief chance to bind before TXT is built.
    ///
    /// `serve(over:)` starts transports in order, so an HTTP sibling is usually
    /// bound by the time this listener is ready — but "usually" is not a guarantee,
    /// and a sibling on an ephemeral port publishes nothing until it binds. Waiting
    /// briefly here is the difference between advertising the `http` endpoint and
    /// silently omitting it forever.
    ///
    /// Bounded and best-effort: if no sibling was configured there is nothing to
    /// wait for, and if one never binds the advertisement simply goes out without
    /// the key rather than blocking the transport.
    private func waitForSiblingHTTPEndpoint(timeout: TimeInterval = 2) async {
        guard httpEndpointProvider != nil, httpEndpoint == nil else { return }
        let deadline = Date().addingTimeInterval(timeout)
        while httpEndpoint == nil, Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        if httpEndpoint == nil {
            logger.debug("Sibling HTTP endpoint not bound in time; advertising without the http entry.")
        }
    }

    /// Re-publishes the `.localNetwork` advertisement once the port is known.
    ///
    /// That scope is advertised by `NWListener`, whose service is configured
    /// before anything binds — so its TXT record is built too early to include a
    /// sibling HTTP endpoint. Re-assigning the service updates the advertisement
    /// in place.
    private func republishNetworkService(generation: UInt64) async {
        guard !scope.isLocalOnly, httpEndpoint != nil else { return }
        await state.updateService(
            NWListener.Service(
                name: advertisedInstanceName,
                type: MCPBonjour.serviceType,
                domain: scope.domain,
                txtRecord: NWTXTRecord(txtRecord.entries)
            ),
            generation: generation
        )
    }

    /// Publishes the local-only DNS-SD registration for the local scopes.
    ///
    /// `.localNetwork` is advertised by `NWListener` itself, so this is a no-op there.
    ///
    /// A failure here is retried rather than merely logged. An unadvertised
    /// listener looks healthy from the server side while every client reports
    /// `serviceNotFound` — the same "working server, blamed network" shape this
    /// redesign exists to remove — and mDNSResponder being briefly unavailable is
    /// exactly the transient the listener path already retries.
    internal func publishLocalService(on port: UInt16, generation: UInt64, attempt: Int = 0) async {
        guard scope.isLocalOnly else { return }

        do {
            let registration = try LocalOnlyRegistration(
                name: advertisedInstanceName,
                type: MCPBonjour.serviceType,
                domain: scope.domain,
                port: port,
                txtRecord: txtRecord
            )
            guard await state.setLocalRegistration(registration, generation: generation) else {
                registration.stop()
                return
            }
            resolvedInstanceName = registration.resolvedName ?? advertisedInstanceName
            if attempt > 0 {
                logger.info("Local-only Bonjour registration succeeded after \(attempt) retries.")
            }
        } catch {
            let delay = min(UInt64(1) << UInt64(min(attempt, 5)), TCPBonjourTransport.maxRetryDelay)
            logger.error("""
                Could not advertise local-only Bonjour service "\(advertisedInstanceName)": \(error). \
                The listener is up on port \(port) but undiscoverable; retrying in \(delay)s.
                """)
            scheduleRegistrationRetry(
                afterDelay: delay, port: port, generation: generation, attempt: attempt + 1
            )
        }
    }

    /// Retries a failed local-only registration, leaving the listener in place.
    private func scheduleRegistrationRetry(
        afterDelay delay: UInt64, port: UInt16, generation: UInt64, attempt: Int
    ) {
        let task = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: delay * 1_000_000_000)
            } catch {
                return  // cancelled
            }
            guard let self, await self.state.running() else { return }
            await self.publishLocalService(on: port, generation: generation, attempt: attempt)
        }

        Task {
            await state.setRetryTask(task)
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
