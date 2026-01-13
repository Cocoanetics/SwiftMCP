#if canImport(Network)
import Foundation
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
        case .bonjour(let serviceName, let domain):
            return try await resolveBonjourEndpoint(serviceName: serviceName, domain: domain)
        }
    }

    private func resolveBonjourEndpoint(serviceName: String?, domain: String) async throws -> NWEndpoint {
        let parameters = makeParameters()
        let browser = NWBrowser(for: .bonjour(type: config.serviceType, domain: domain), using: parameters)
        self.browser = browser

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<NWEndpoint, Error>) in
            let oneShot = OneShot()
            let finish: @Sendable (Result<NWEndpoint, Error>) -> Void = { result in
                Task {
                    await oneShot.run {
                        Task {
                            await self.finishBonjour(result, continuation: continuation)
                        }
                    }
                }
            }

            browser.browseResultsChangedHandler = { results, _ in
                let matching = results.compactMap { result -> NWEndpoint? in
                    switch result.endpoint {
                    case .service(let name, _, _, _):
                        if let serviceName,
                           !name.localizedCaseInsensitiveContains(serviceName) {
                            return nil
                        }
                        return result.endpoint
                    default:
                        return nil
                    }
                }

                if let endpoint = matching.first ?? results.first?.endpoint {
                    finish(.success(endpoint))
                }
            }

            browser.stateUpdateHandler = { state in
                if case .failed(let error) = state {
                    finish(.failure(error))
                }
            }

            browser.start(queue: queue)

            if config.timeout > 0 {
                Task {
                    let delay = UInt64(config.timeout * 1_000_000_000)
                    try await Task.sleep(nanoseconds: delay)
                    finish(.failure(MCPServerProxyError.communicationError("Bonjour discovery timed out")))
                }
            }
        }
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
import Foundation

/// Stub implementation for platforms without Network framework.
public final actor TCPConnection: StdioConnection {
    public init(config: MCPServerTcpConfig) {
    }

    public func start() async throws {
        throw MCPServerProxyError.unsupportedPlatform("TCP connections require the Network framework.")
    }

    public func lines() async -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: MCPServerProxyError.unsupportedPlatform("TCP connections require the Network framework."))
        }
    }

    public func write(_ data: Data) async {
    }

    public func stop() async {
    }
}
#endif
