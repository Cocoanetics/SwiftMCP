#if Client
import SwiftCross

extension MCPServerProxy {
    /// Connects to the MCP server and establishes an SSE, TCP, or stdio connection.
    /// - Parameters:
    ///   - clientName: The client name sent during the MCP handshake.
    ///   - clientVersion: The client version sent during the MCP handshake.
    public func connect(
        clientName: String = "swiftmcp-client",
        clientVersion: String = "1.0.0"
    ) async throws {
        isDisconnecting = false
        streamFailure = nil
        endpointURL = nil
        // Clear any version carried over from a previous connection so the
        // re-`initialize` below proposes `latest` afresh rather than echoing a
        // stale negotiated version in its `MCP-Protocol-Version` header.
        negotiatedProtocolVersion = nil

        // Reset the session identity so a reconnect after `.sessionInvalidated`
        // starts clean. The stdio/TCP cases immediately assign a fresh
        // client-side UUID below; the SSE case must NOT send a stale
        // `Mcp-Session-Id` on the initialize POST, because a server that has
        // forgotten the session rejects it as "Unknown session" before it can
        // create a new one. (#125)
        sessionID = nil

        // Retire any stream left over from a previous connection: cancel it and
        // advance the generation so reconnecting on the same proxy neither leaves
        // a second general-SSE loop running nor lets that stale loop's eventual
        // `handleStreamTermination` fail this connection's requests. (#125)
        retireStream()

        switch config {
        case .stdio(let stdioConfig):
            #if os(macOS) || os(Linux) || os(Windows)
                sessionID = UUID().uuidString
                // Spawn the server over JSONFoundation's swift-subprocess stdio
                // transport — the shared, lock-free child-process transport LSP and
                // SwiftACP use. The command keeps SwiftMCP's `/bin/zsh -lc` wrapping
                // so a login shell resolves PATH and the user's environment.
                let shellCommand = ([stdioConfig.command] + stdioConfig.args)
                    .joined(separator: " ")
                let launch = ProcessLaunch(
                    executable: "/bin/zsh",
                    arguments: ["-lc", shellCommand],
                    environment: stdioConfig.environment,
                    workingDirectory: stdioConfig.workingDirectory
                )
                let transport = StdioMessageTransport(
                    endpoint: .childProcess(launch),
                    framing: LineFraming()
                )
                await startLinePeer(transport: transport)
                try await initialize(clientName: clientName, clientVersion: clientVersion)
            #else
                throw MCPServerProxyError.unsupportedPlatform(
                    "Stdio-based MCP servers require Process support."
                )
            #endif

        case .stdioHandles(let server):
            sessionID = UUID().uuidString
            // Talk to the embedded server over JSONFoundation's in-memory loopback
            // pair — no OS pipes — with the same peer driving the client end.
            let loopback = InProcessServerLoopback(server: server)
            loopback.start()
            inProcessLoopback = loopback
            await startLinePeer(transport: loopback.clientTransport)
            try await initialize(clientName: clientName, clientVersion: clientVersion)

        case .tcp(let tcpConfig):
            try await connectTCP(
                tcpConfig: tcpConfig,
                clientName: clientName,
                clientVersion: clientVersion
            )

        case .sse(let sseConfig):
            try await connectSSE(
                sseConfig: sseConfig,
                clientName: clientName,
                clientVersion: clientVersion
            )
        }
    }

    private func connectTCP(
        tcpConfig: MCPServerTcpConfig,
        clientName: String,
        clientVersion: String
    ) async throws {
        sessionID = UUID().uuidString
        let resolvedConfig = resolveTcpConfig(tcpConfig)
        let transport = try await makeTCPTransport(resolvedConfig)
        await startLinePeer(transport: transport)
        try await initialize(clientName: clientName, clientVersion: clientVersion)
    }

    /// Builds the line transport for a TCP connection. A direct host:port uses
    /// JSONFoundation's POSIX-socket ``TCPClientTransport`` (no Network framework,
    /// so it works on Linux too); Bonjour discovery stays on the Network-framework
    /// ``TCPConnection``, wrapped onto the shared transport seam.
    private func makeTCPTransport(
        _ config: MCPServerTcpConfig
    ) async throws -> any JSONRPCMessageTransport {
        switch config.endpoint {
        case .direct(let host, let port):
            #if os(Windows)
                throw MCPServerProxyError.unsupportedPlatform(
                    "Direct TCP connections are not supported on this platform."
                )
            #else
                // `TCPClientTransport.init` blocks while it resolves and connects,
                // so run it off the actor to avoid stalling the proxy.
                return try await Task.detached {
                    try TCPClientTransport(host: host, port: port, framing: LineFraming())
                }.value
            #endif
        case .bonjour:
            #if canImport(Network)
                let connection = TCPConnection(config: config)
                try await connection.start()
                return LineConnectionTransport(connection: connection)
            #else
                throw MCPServerProxyError.unsupportedPlatform(
                    "Bonjour TCP discovery requires the Network framework."
                )
            #endif
        }
    }

    private func connectSSE(
        sseConfig: MCPServerSseConfig,
        clientName: String,
        clientVersion: String
    ) async throws {
        try await connectSSEStream(
            sseConfig: sseConfig,
            clientName: clientName,
            clientVersion: clientVersion
        )
    }

    /// Disconnects from the MCP server.
    public func disconnect() async {
        isDisconnecting = true
        let disconnectError = CancellationError()
        streamFailure = disconnectError
        failPendingResponseTasks(with: disconnectError)
        if let endpointContinuation {
            self.endpointContinuation = nil
            endpointContinuation.resume(throwing: disconnectError)
        }

        retireStream()
        endpointURL = nil

        switch config {
        case .stdio, .stdioHandles, .tcp:
            // Closing the peer fails its in-flight requests and tears down the
            // transport it owns (which stops the underlying connection).
            await linePeer?.close()
            linePeer = nil
            lineTransport = nil
            inProcessLoopback?.stop()
            inProcessLoopback = nil
        case .sse:
            break
        }

        sessionID = nil
    }

    /// Drives a line-based transport (stdio / TCP / in-process) through the shared
    /// ``JSONRPCPeer`` in pull mode: the peer owns the read loop, correlates our
    /// requests with their responses by id, dispatches inbound notifications to
    /// our handlers, and replies to inbound requests (e.g. `ping`).
    internal func startLinePeer(transport: any JSONRPCMessageTransport) async {
        let peer = JSONRPCPeer(transport: transport)
        await peer.setHandlers(
            request: { [weak self] method, params in
                guard let self else {
                    return .failure(.internalError("client released"))
                }
                return await self.handleLinePeerRequest(method: method, params: params)
            },
            notification: { [weak self] method, params in
                await self?.handleNotification(method: method, params: params)
            }
        )
        lineTransport = transport
        linePeer = peer
        await peer.start()
    }

    /// Handles a server-initiated request arriving over a line transport. The MCP
    /// client answers `ping`; anything else it does not implement is rejected with
    /// method-not-found (rather than silently leaving the server waiting).
    internal func handleLinePeerRequest(
        method: String,
        params: JSONValue?
    ) async -> Result<JSONValue, JSONRPCError> {
        switch method {
        case "ping":
            return .success(.object([:]))
        default:
            logger.debug("[MCP DEBUG] Unhandled client request: \(method)")
            return .failure(.methodNotFound(method))
        }
    }

    /// Routes a notification delivered by the line peer through the same handler
    /// stack the SSE path uses.
    internal func handleNotification(method: String, params: JSONValue?) async {
        await handleNotification(
            JSONRPCMessage.JSONRPCNotificationData(method: method, params: params)
        )
    }

    internal func failPendingResponseTasks(with error: Error) {
        responses.failAll(with: error)
    }

    /// Retire the active stream task: cancel it and advance the generation so a
    /// late `handleStreamTermination` from the now-stale task is ignored.
    internal func retireStream() {
        streamTask?.cancel()
        streamTask = nil
        streamGeneration += 1
    }

    internal func handleStreamTermination(_ error: Error, generation: Int) {
        // Ignore terminations from a stream that has since been retired by a
        // reconnect or disconnect. Without this, a leftover general-SSE loop that
        // hits the server's "unknown session" 404 would fail the requests of the
        // connection that replaced it (e.g. a reconnect's `initialize`). (#125)
        guard generation == streamGeneration else {
            return
        }
        guard !isDisconnecting else {
            return
        }

        let failure: Error
        if let serverError = error as? MCPServerProxyError {
            failure = serverError
        } else {
            failure = MCPServerProxyError.communicationError(error.localizedDescription)
        }

        if streamFailure == nil {
            streamFailure = failure
        }

        let terminalError = streamFailure ?? failure
        failPendingResponseTasks(with: terminalError)

        if let endpointContinuation {
            self.endpointContinuation = nil
            endpointContinuation.resume(throwing: terminalError)
        }
    }

    internal func initialize(clientName: String, clientVersion: String) async throws {
        let requestId = nextRequestID()
        var params: JSONDictionary = [
            "protocolVersion": .string(MCPProtocolVersion.latest),
            "clientInfo": .object([
                "name": .string(clientName),
                "version": .string(clientVersion)
            ]),
            "capabilities": .object(buildClientCapabilities())
        ]

        // Add base metadata if present
        if !meta.isEmpty {
            params["_meta"] = .object(meta)
        }

        let request = JSONRPCMessage.request(
            id: requestId,
            method: "initialize",
            params: .object(params)
        )
        let response = try await send(request)

        guard case let .response(responseData) = response,
              let result = responseData.result?.dictionaryValue else {
            throw MCPServerProxyError.communicationError("Invalid initialize response")
        }

        let rawServerDescription = extractServerDescription(from: result)
        let initResult = try Self.decodeJSONPayload(result, as: InitializeResult.self)
        // The server echoes the agreed revision, which may be older than the
        // `latest` we proposed; from here on the client acts on this version.
        negotiatedProtocolVersion = initResult.protocolVersion
        serverName = initResult.serverInfo.name
        serverVersion = initResult.serverInfo.version
        serverDescription = initResult.serverInfo.description ?? rawServerDescription
        serverTitle = initResult.serverInfo.title
        serverWebsiteUrl = initResult.serverInfo.websiteUrl
        serverIcons = initResult.serverInfo.icons ?? []
        serverCapabilities = initResult.capabilities
        if service == nil {
            service = serverName
        }
        let nameDescription = serverName ?? "unknown"
        let versionDescription = serverVersion ?? "unknown"
        logger.info(
            "Connected to MCP server: \(nameDescription) version \(versionDescription)"
        )

        // Send the required notifications/initialized to complete the MCP handshake.
        // Servers may ignore subsequent requests until this notification is received.
        try await sendNotification(JSONRPCMessage.notification(method: "notifications/initialized"))
    }

    /// Sends a JSON-RPC notification (fire-and-forget, no response expected).
    internal func sendNotification(_ message: JSONRPCMessage) async throws {
        switch config {
        case .stdio, .stdioHandles, .tcp:
            guard let linePeer else {
                throw MCPServerProxyError.communicationError("Not connected to line-based server")
            }
            guard case .notification(let notification) = message else {
                throw MCPServerProxyError.communicationError(
                    "sendNotification(_:) requires a notification message"
                )
            }
            try await linePeer.sendNotification(
                method: notification.method,
                params: notification.params
            )

        case .sse(let sseConfig):
            let data = try JSONRPCMessage.makeEncoder().encode(message)
            try await sendSSENotification(data: data, sseConfig: sseConfig)
        }
    }

    private func sendSSENotification(
        data: Data,
        sseConfig: MCPServerSseConfig
    ) async throws {
        guard let url = endpointURL
            ?? (isStreamableMCPURL(sseConfig.url) ? sseConfig.url : nil) else {
            throw MCPServerProxyError.communicationError("Not connected to server")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = data
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        configureSSEPOSTRequest(&request, sseConfig: sseConfig)
        let (_, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw MCPServerProxyError.communicationError(
                "Notification rejected by server (HTTP \(httpResponse.statusCode))"
            )
        }
    }

    internal func resolveTcpConfig(_ config: MCPServerTcpConfig) -> MCPServerTcpConfig {
        guard case .bonjour(let serviceName, let domain) = config.endpoint,
              serviceName == nil,
              let service else {
            return config
        }
        return MCPServerTcpConfig(
            serviceName: service,
            domain: domain,
            serviceType: config.usesDefaultServiceType ? nil : config.serviceType,
            timeout: config.timeout,
            preferIPv4: config.preferIPv4
        )
    }
}
#endif
