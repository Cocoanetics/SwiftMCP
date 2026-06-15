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
            sessionID = UUID().uuidString
            lineConnection = MCPServerProcess(config: stdioConfig)
            try await startLineConnection()
            try await initialize(clientName: clientName, clientVersion: clientVersion)

        case .stdioHandles(let server):
            sessionID = UUID().uuidString
            lineConnection = InProcessStdioBridge(server: server)
            try await startLineConnection()
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
        #if canImport(Network)
            sessionID = UUID().uuidString
            let resolvedConfig = resolveTcpConfig(tcpConfig)
            lineConnection = TCPConnection(config: resolvedConfig)
            try await startLineConnection()
            try await initialize(clientName: clientName, clientVersion: clientVersion)
        #else
            throw MCPServerProxyError.unsupportedPlatform(
                "TCP connections require the Network framework."
            )
        #endif
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
            await lineConnection?.stop()
            lineConnection = nil
        case .sse:
            break
        }

        sessionID = nil
    }

    internal func startLineConnection() async throws {
        guard let lineConnection else {
            throw MCPServerProxyError.communicationError("Not connected to line-based server")
        }
        try await lineConnection.start()

        let generation = streamGeneration
        streamTask = Task {
            do {
                let lines = await lineConnection.lines()
                for try await data in lines {
                    await processIncomingMessage(data: data)
                }
                self.handleStreamTermination(
                    MCPServerProxyError.communicationError(
                        "Connection closed by server before response was received"
                    ),
                    generation: generation
                )
            } catch is CancellationError {
                // Pending requests are cancelled in disconnect().
            } catch {
                logger.error("[MCP DEBUG] Stream error: \(error.localizedDescription)")
                self.handleStreamTermination(error, generation: generation)
            }
        }
    }

    internal func failPendingResponseTasks(with error: Error) {
        let pending = responseTasks
        responseTasks.removeAll()

        for (_, continuation) in pending {
            continuation.resume(throwing: error)
        }
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
            params: params
        )
        let response = try await send(request)

        guard case let .response(responseData) = response,
              let result = responseData.result else {
            throw MCPServerProxyError.communicationError("Invalid initialize response")
        }

        let rawServerDescription = extractServerDescription(from: result)
        let initResult = try Self.decodeJSONPayload(result, as: InitializeResult.self)
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
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(message)

        switch config {
        case .stdio, .stdioHandles, .tcp:
            guard let lineConnection else {
                throw MCPServerProxyError.communicationError("Not connected to line-based server")
            }
            await lineConnection.write(data + Data("\n".utf8))

        case .sse(let sseConfig):
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
            serviceType: config.serviceType,
            timeout: config.timeout,
            preferIPv4: config.preferIPv4
        )
    }
}
#endif
