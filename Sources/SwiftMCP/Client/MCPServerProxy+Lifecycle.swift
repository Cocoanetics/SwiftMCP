import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

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
        #if os(Linux)
            try await connectSSELinux(
                sseConfig: sseConfig,
                clientName: clientName,
                clientVersion: clientVersion
            )
        #else
            if #available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, macCatalyst 15.0, *) {
                try await connectSSEApple(
                    sseConfig: sseConfig,
                    clientName: clientName,
                    clientVersion: clientVersion
                )
            } else {
                throw MCPServerProxyError.unsupportedPlatform(
                    "SSE client connections require macOS 12.0 or newer."
                )
            }
        #endif
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

        streamTask?.cancel()
        streamTask = nil
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

        streamTask = Task {
            do {
                let lines = await lineConnection.lines()
                for try await data in lines {
                    await processIncomingMessage(data: data)
                }
                self.handleStreamTermination(
                    MCPServerProxyError.communicationError(
                        "Connection closed by server before response was received"
                    )
                )
            } catch is CancellationError {
                // Pending requests are cancelled in disconnect().
            } catch {
                logger.error("[MCP DEBUG] Stream error: \(error.localizedDescription)")
                self.handleStreamTermination(error)
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

    internal func handleStreamTermination(_ error: Error) {
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
            "protocolVersion": .string(HTTPSSETransport.latestProtocolVersion),
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
