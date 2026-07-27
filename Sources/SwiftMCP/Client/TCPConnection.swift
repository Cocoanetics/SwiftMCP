#if Client
import Foundation

#if canImport(Network)
import Network
import Logging

/// A newline-delimited TCP connection used by MCPServerProxy.
public final actor TCPConnection: StdioConnection {
    private actor OneShot {
        private var hasRun = false

        func run(_ action: () -> Void) {
            guard !hasRun else { return }
            hasRun = true
            action()
        }
    }

    /// One discovered MCP service, decoupled from `NWBrowser.Result`.
    ///
    /// The selection rules are pure over this type so they stay unit-testable —
    /// `NWBrowser.Result` cannot be constructed by a test, so selecting directly
    /// over it would silently delete discovery's only test coverage.
    internal struct DiscoveredService: Sendable, Equatable {
        let instanceName: String
        let endpoint: NWEndpoint
        let txtRecord: BonjourTXTRecord?
        let isLoopback: Bool

        init(instanceName: String, endpoint: NWEndpoint, txtRecord: BonjourTXTRecord? = nil, isLoopback: Bool) {
            self.instanceName = instanceName
            self.endpoint = endpoint
            self.txtRecord = txtRecord
            self.isLoopback = isLoopback
        }

        /// Builds a service from a browse result, or `nil` for non-Bonjour endpoints.
        init?(result: NWBrowser.Result) {
            guard case .service(let name, _, _, _) = result.endpoint else { return nil }
            self.instanceName = name
            self.endpoint = result.endpoint
            if case .bonjour(let record) = result.metadata {
                var entries = [String: String]()
                for key in record.dictionary.keys { entries[key] = record[key] }
                self.txtRecord = entries.isEmpty ? nil : BonjourTXTRecord(entries: entries)
            } else {
                self.txtRecord = nil
            }
            self.isLoopback = result.interfaces.contains { $0.type == .loopback }
        }
    }

    private let config: MCPServerTcpConfig
    private let logger = Logger(label: "com.cocoanetics.SwiftMCP.Client.TCPConnection")
    private let lineBuffer = LineBuffer()
    private let queue = DispatchQueue(label: "com.cocoanetics.SwiftMCP.Client.TCPConnection")

    private var connection: NWConnection?
    private var browser: NWBrowser?

    public init(config: MCPServerTcpConfig) {
        self.config = config
    }

    public func start() async throws {
        guard connection == nil else { return }
        let endpoint = try await resolveEndpoint()
        let parameters = makeParameters()
        let connection = NWConnection(to: endpoint, using: parameters)
        self.connection = connection

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let oneShot = OneShot()
            connection.stateUpdateHandler = { state in
                Task {
                    switch state {
                    case .ready:
                        await oneShot.run {
                            continuation.resume()
                        }
                    case .failed(let error):
                        await oneShot.run {
                            continuation.resume(throwing: error)
                        }
                    case .cancelled:
                        await oneShot.run {
                            continuation.resume(throwing: CancellationError())
                        }
                    default:
                        break
                    }
                }
            }

            connection.start(queue: queue)
        }
    }

    public func lines() async -> AsyncThrowingStream<String, Error> {
        let connection = self.connection
        return AsyncThrowingStream { continuation in
            guard let connection else {
                continuation.finish(throwing: MCPServerProxyError.communicationError("TCP connection not started"))
                return
            }

            Task {
                await self.receiveNext(connection: connection, continuation: continuation)
            }
        }
    }

    public func write(_ data: Data) async {
        guard let connection else { return }
        connection.send(content: data, completion: .contentProcessed { [logger] error in
            if let error {
                logger.error("TCP send failed: \(error)")
            }
        })
    }

    public func stop() async {
        connection?.cancel()
        connection = nil
        browser?.cancel()
        browser = nil
    }

    private func makeParameters() -> NWParameters {
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = false
        if config.preferIPv4,
           let ipOptions = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            ipOptions.version = .v4
        }
        return parameters
    }

    private func resolveEndpoint() async throws -> NWEndpoint {
        switch config.endpoint {
        case .direct(let host, let port):
            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                throw MCPServerProxyError.communicationError("Invalid TCP port: \(port)")
            }
            return .hostPort(host: NWEndpoint.Host(host), port: nwPort)
        case .bonjour:
            return try await resolveBonjourEndpoint()
        }
    }

    /// Browses for the configured service and returns its endpoint.
    ///
    /// One browser, not one per service type — there is only one service type now.
    /// The descriptor depends on the scope, because the two cannot be combined:
    /// `.bonjourWithTXTRecord` delivers TXT but cannot see local-only registrations,
    /// while plain `.bonjour` sees them but reports no metadata. That splits along
    /// exactly the right line — the scope that needs TXT for filtering is the one
    /// where TXT works, and the scope where it doesn't is a named lookup that
    /// fast-connects without it.
    private func resolveBonjourEndpoint() async throws -> NWEndpoint {
        let scope = config.scope
        let descriptor: NWBrowser.Descriptor = scope.isLocalOnly
            ? .bonjour(type: MCPBonjour.serviceType, domain: scope.domain)
            : .bonjourWithTXTRecord(type: MCPBonjour.serviceType, domain: scope.domain)
        let browser = NWBrowser(for: descriptor, using: makeParameters())
        self.browser = browser

        let derivedName = config.derivedInstanceName
        let baseName = config.baseInstanceName

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<NWEndpoint, Error>) in
            let oneShot = OneShot()
            let finish: @Sendable (Result<NWEndpoint, Error>) -> Void = { result in
                Task {
                    await oneShot.run {
                        Task { await self.finishBonjour(result, continuation: continuation) }
                    }
                }
            }

            browser.browseResultsChangedHandler = { results, _ in
                let services = results.compactMap(DiscoveredService.init(result:))
                do {
                    if let match = try Self.selectService(
                        from: services, derivedName: derivedName, baseName: baseName, scope: scope
                    ) {
                        finish(.success(match.endpoint))
                    }
                } catch {
                    // Ambiguity is decided the moment the results arrive; there is
                    // nothing to gain by waiting out the timeout to report it.
                    finish(.failure(error))
                }
            }

            browser.stateUpdateHandler = { state in
                guard case .failed(let error) = state else { return }
                finish(.failure(error))
            }

            browser.start(queue: queue)

            if config.timeout > 0 {
                Task {
                    let delay = UInt64(config.timeout * 1_000_000_000)
                    try await Task.sleep(nanoseconds: delay)
                    finish(.failure(MCPServerProxyError.serviceNotFound(instanceName: baseName)))
                }
            }
        }
    }

    /// Picks the service to connect to, or `nil` to keep browsing.
    ///
    /// Pure over ``DiscoveredService`` so it can be tested without a live network.
    ///
    /// - Throws: ``MCPServerProxyError/ambiguousService(candidates:)`` when a
    ///   *nameless* browse sees more than one candidate. A named lookup cannot be
    ///   ambiguous: mDNS enforces instance-name uniqueness per (type, domain) by
    ///   conflict-renaming, so one exact match is the answer the moment it arrives.
    ///   That is what lets a named lookup connect immediately rather than waiting
    ///   out a settle period.
    internal static func selectService(
        from services: [DiscoveredService],
        derivedName: String?,
        baseName: String?,
        scope: DiscoveryScope
    ) throws -> DiscoveredService? {
        // At local scope, anything not reachable on loopback is not ours.
        let candidates = scope.isLocalOnly ? services.filter(\.isLoopback) : services

        if let derivedName {
            // Local scopes: the advertised name is derivable, so match it exactly.
            return candidates.first { $0.instanceName.matchesInstanceName(derivedName) }
        }

        if let baseName {
            // .localNetwork: the server qualified with its own host name, which we
            // cannot reconstruct. Match the TXT `name` entry, falling back to the
            // qualified-name prefix when TXT has not arrived — absent metadata means
            // unknown, never mismatched.
            return candidates.first { service in
                if let advertised = service.txtRecord?.serverName {
                    return advertised.matchesInstanceName(baseName)
                }
                return service.instanceName.normalizedInstanceName
                    .hasPrefix(baseName.normalizedInstanceName)
            }
        }

        // Nameless browse: only unambiguous when exactly one service is in scope.
        guard !candidates.isEmpty else { return nil }
        guard candidates.count == 1 else {
            throw MCPServerProxyError.ambiguousService(
                candidates: candidates.map(\.instanceName).sorted()
            )
        }
        return candidates[0]
    }

    private func finishBonjour(
        _ result: Result<NWEndpoint, Error>,
        continuation: CheckedContinuation<NWEndpoint, Error>
    ) async {
        browser?.cancel()
        browser = nil
        continuation.resume(with: result)
    }

    private func receiveNext(
        connection: NWConnection,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async {
        let lineBuffer = self.lineBuffer
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, isComplete, error in
            if let data, !data.isEmpty {
                Task {
                    await lineBuffer.append(data)
                    let lines = await lineBuffer.processLines()
                    for line in lines {
                        continuation.yield(line)
                    }
                }
            }

            if let error {
                continuation.finish(throwing: error)
                return
            }

            if isComplete {
                Task {
                    if let remaining = await lineBuffer.getRemaining() {
                        continuation.yield(remaining)
                    }
                    continuation.finish()
                }
                return
            }

            Task {
                await self.receiveNext(connection: connection, continuation: continuation)
            }
        }
    }
}
#else

/// Stub implementation for platforms without Network framework.
public final actor TCPConnection: StdioConnection {
    public init(config: MCPServerTcpConfig) {
    }

    public func start() async throws {
        throw MCPServerProxyError.unsupportedPlatform("TCP connections require the Network framework.")
    }

    public func lines() async -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(
                throwing: MCPServerProxyError.unsupportedPlatform(
                    "TCP connections require the Network framework."
                )
            )
        }
    }

    public func write(_ data: Data) async {
    }

    public func stop() async {
    }
}
#endif
#endif
