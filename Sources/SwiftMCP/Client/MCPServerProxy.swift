import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Logging

/// A proxy for interacting with an MCP server over stdio, TCP, or SSE.
public final actor MCPServerProxy: Sendable {
    private struct NotificationHandlerBox: Sendable {
        let payloadTypeDescription: String
        let handle: @Sendable (MCPServerProxy, JSONRPCMessage.JSONRPCNotificationData) async throws -> Void
    }

    private enum NotificationMethod {
        static let log = "notifications/message"
        static let progress = "notifications/progress"
    }

    public let logger = Logger(label: "com.cocoanetics.SwiftMCP.MCPServerProxy")

    /// The configuration for the MCP server.
    public let config: MCPServerConfig

    /// Optional Bonjour service name to prefer during discovery.
    public var service: String?

    /// Specifies whether the list of tools from the server should be cached.
    public let cacheToolsList: Bool
    
    /// Base metadata included in _meta for ALL requests (e.g., accessToken).
    public var meta: [String: AnyCodable] = [:]

    private var cachedTools: [MCPTool]?
    private var requestIdSequence: Int = 0

    private func nextRequestID() -> JSONRPCID {
        defer { requestIdSequence += 1 }
        return .int(requestIdSequence)
    }

    private var responseTasks: [JSONRPCID: CheckedContinuation<JSONRPCMessage, Error>] = [:]
    private var streamFailure: Error?
    private var isDisconnecting = false

    public private(set) var endpointURL: URL?
    public private(set) var sessionID: String?
    private var streamTask: Task<Void, Error>?

    public private(set) var serverName: String?
    public private(set) var serverVersion: String?
    public private(set) var serverDescription: String?
    public private(set) var serverCapabilities: ServerCapabilities?

    private var notificationHandlers: [String: NotificationHandlerBox] = [:]

    /// Optional handler for log notifications from the server.
    public var logNotificationHandler: (any MCPServerProxyLogNotificationHandling)? {
        didSet {
            updateLogNotificationRegistration()
        }
    }

    /// Optional handler for progress notifications from the server.
    public var progressNotificationHandler: (any MCPServerProxyProgressNotificationHandling)? {
        didSet {
            updateProgressNotificationRegistration()
        }
    }

    /// Updates the log notification handler.
    public func setLogNotificationHandler(_ handler: (any MCPServerProxyLogNotificationHandling)?) {
        logNotificationHandler = handler
    }

    /// Updates the progress notification handler.
    public func setProgressNotificationHandler(_ handler: (any MCPServerProxyProgressNotificationHandling)?) {
        progressNotificationHandler = handler
    }

    /// Registers a typed handler for a JSON-RPC notification.
    public func setNotificationHandler<Payload>(
        _ method: String,
        as payloadType: Payload.Type = Payload.self,
        handler: @escaping @Sendable (Payload) async -> Void
    ) where Payload: Decodable, Payload: Sendable {
        notificationHandlers[method] = NotificationHandlerBox(
            payloadTypeDescription: String(reflecting: payloadType),
            handle: { _, notification in
                let payload = try Self.decodeNotificationPayload(from: notification, as: payloadType)
                await handler(payload)
            }
        )
    }

    /// Removes the registered handler for a JSON-RPC notification.
    public func removeNotificationHandler(for method: String) {
        notificationHandlers.removeValue(forKey: method)
    }

    private var lineConnection: (any StdioConnection)?
    private var endpointContinuation: CheckedContinuation<URL, Error>?

    public init(config: MCPServerConfig, cacheToolsList: Bool = false) {
        self.config = config
        self.service = nil
        self.cacheToolsList = cacheToolsList
    }

    /// Connects to the MCP server and establishes an SSE, TCP, or stdio connection.
    public func connect() async throws {
        isDisconnecting = false
        streamFailure = nil
        endpointURL = nil
        sessionID = nil

        switch config {
            case .stdio(let stdioConfig):
                lineConnection = MCPServerProcess(config: stdioConfig)
                try await startLineConnection()
                try await initialize()

            case .stdioHandles(let server):
                lineConnection = InProcessStdioBridge(server: server)
                try await startLineConnection()
                try await initialize()

            case .tcp(let tcpConfig):
#if canImport(Network)
                let resolvedConfig = resolveTcpConfig(tcpConfig)
                lineConnection = TCPConnection(config: resolvedConfig)
                try await startLineConnection()
                try await initialize()
#else
                throw MCPServerProxyError.unsupportedPlatform("TCP connections require the Network framework.")
#endif

            case .sse(let sseConfig):
#if os(Linux)
                try await connectSSELinux(sseConfig: sseConfig)
#else
                if #available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, macCatalyst 15.0, *) {
                    try await connectSSEApple(sseConfig: sseConfig)
                } else {
                    throw MCPServerProxyError.unsupportedPlatform("SSE client connections require macOS 12.0 or newer.")
                }
#endif
        }
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
        sessionID = nil

        switch config {
        case .stdio, .stdioHandles, .tcp:
            await lineConnection?.stop()
            lineConnection = nil
        case .sse:
            break
        }
    }

    /// Lists all available tools from the server.
    public func listTools() async throws -> [MCPTool] {
        if cacheToolsList, let cachedTools = cachedTools {
            return cachedTools
        }

        let result = try await requestResult(method: "tools/list")
        let tools: [MCPTool] = try decodeResultField("tools", from: result, method: "tools/list")

        if cacheToolsList {
            cachedTools = tools
        }

        return tools
    }

    /// Lists all static resources available from the server.
    public func listResources() async throws -> [SimpleResource] {
        let result = try await requestResult(method: "resources/list")
        return try decodeResultField("resources", from: result, method: "resources/list")
    }

    /// Lists all resource templates available from the server.
    public func listResourceTemplates() async throws -> [SimpleResourceTemplate] {
        let result = try await requestResult(method: "resources/templates/list")
        return try decodeResultField("resourceTemplates", from: result, method: "resources/templates/list")
    }

    /// Reads a resource at the specified URI.
    public func readResource(uri: URL) async throws -> [GenericResourceContent] {
        let result = try await requestResult(
            method: "resources/read",
            params: ["uri": AnyCodable(uri.absoluteString)]
        )
        return try decodeResultField("contents", from: result, method: "resources/read")
    }

    /// Lists all prompts available from the server.
    public func listPrompts() async throws -> [Prompt] {
        let result = try await requestResult(method: "prompts/list")
        return try decodeResultField("prompts", from: result, method: "prompts/list")
    }

    /// Gets a prompt by name with optional arguments.
    public func getPrompt(
        name: String,
        arguments: [String: any Sendable] = [:]
    ) async throws -> PromptResult {
        let result = try await requestResult(
            method: "prompts/get",
            params: [
                "name": AnyCodable(name),
                "arguments": AnyCodable(arguments.mapValues(AnyCodable.init))
            ]
        )
        return try decodeResultField("self", from: result, method: "prompts/get", as: PromptResult.self)
    }

    /// Calls a tool by name on the connected MCP server with the provided arguments.
    public func callTool(
        _ name: String,
        arguments: [String: any Sendable] = [:],
        progressToken: AnyCodable? = AnyCodable(UUID().uuidString)
    ) async throws -> String {
        let requestId = nextRequestID()
        let encodableArguments = arguments.mapValues { AnyCodable($0) }
        var params: [String: AnyCodable] = [
            "name": AnyCodable(name),
            "arguments": AnyCodable(encodableArguments)
        ]
        
        // Merge base meta with progressToken
        var requestMeta = meta  // Start with base meta (e.g., accessToken)
        if let progressToken {
            requestMeta["progressToken"] = progressToken
        }
        if !requestMeta.isEmpty {
            params["_meta"] = AnyCodable(requestMeta)
        }
        
        let request = JSONRPCMessage.request(id: requestId, method: "tools/call", params: params)
        let responseMessage = try await send(request)

        let result: [String: AnyCodable]
        switch responseMessage {
        case .response(let responseData):
            guard let responseResult = responseData.result else {
                throw MCPServerProxyError.communicationError("Invalid response type for tools/call, expected JSONRPCResponse")
            }
            result = responseResult
        case .errorResponse(let errorResponse):
            throw MCPServerProxyError.toolError(errorResponse.error.message)
        default:
            throw MCPServerProxyError.communicationError("Invalid response type for tools/call, expected JSONRPCResponse")
        }

        if let isError = result["isError"]?.value as? Bool, isError {
            throw MCPServerProxyError.toolError(errorMessage(from: result) ?? "Tool call failed with an unspecified error.")
        }

        guard let contentValue = result["content"]?.value else {
            throw MCPServerProxyError.communicationError("Invalid content format in tools/call response")
        }
        let contentArray: [Any]
        if let array = contentValue as? [Any] {
            contentArray = array
        } else if let array = contentValue as? [AnyCodable] {
            contentArray = array.map { $0.value }
        } else {
            throw MCPServerProxyError.communicationError("Invalid content format in tools/call response")
        }

        if let text = extractTextPayload(from: contentArray) {
            return text
        }

        if let contentPayload = encodeContentPayload(from: contentArray) {
            return contentPayload
        }

        throw MCPServerProxyError.communicationError("Failed to extract string content from tools/call response")
    }

    /// Invalidates the cached list of tools.
    public func invalidateToolsCache() {
        cachedTools = nil
    }

    /// Sends a JSON-RPC message to the server and waits for the response.
    public func send(_ message: JSONRPCMessage) async throws -> JSONRPCMessage {
        let messageId = message.id
        switch config {
        case .stdio, .stdioHandles, .tcp:
            guard let messageId = messageId else {
                throw MCPServerProxyError.communicationError("Message must have an ID")
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(message)

            let messageWithNewline = data + "\n".data(using: .utf8)!
            guard let lineConnection else {
                throw MCPServerProxyError.communicationError("Not connected to line-based server")
            }

            if let streamFailure {
                throw streamFailure
            }

            await lineConnection.write(messageWithNewline)

            if let streamFailure {
                throw streamFailure
            }

            return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<JSONRPCMessage, Error>) in
                if let streamFailure {
                    continuation.resume(throwing: streamFailure)
                } else {
                    responseTasks[messageId] = continuation
                }
            }

        case .sse(let sseConfig):
            guard let endpointURL = endpointURL else {
                throw MCPServerProxyError.communicationError("Not connected to server")
            }
            if let streamFailure {
                throw streamFailure
            }
            guard let messageId = messageId else {
                throw MCPServerProxyError.communicationError("Message must have an ID")
            }
            let session = URLSession(configuration: .default)
            var urlRequest = URLRequest(url: endpointURL)
            urlRequest.httpMethod = "POST"
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            configureSSEPOSTRequest(&urlRequest, sseConfig: sseConfig)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(message)
            urlRequest.httpBody = data

            return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<JSONRPCMessage, Error>) in
                if let streamFailure {
                    continuation.resume(throwing: streamFailure)
                    return
                }

                responseTasks[messageId] = continuation

                Task {
                    do {
                        let (responseData, response) = try await session.data(for: urlRequest)
                        guard let httpResponse = response as? HTTPURLResponse else {
                            throw MCPServerProxyError.communicationError("Invalid HTTP response")
                        }

                        switch httpResponse.statusCode {
                        case 200, 202:
                            if let updatedSessionID = httpResponse.value(forHTTPHeaderField: "Mcp-Session-Id") {
                                sessionID = updatedSessionID
                            }

                            // Some servers reply immediately in the HTTP body even for 202.
                            if let responseMessage = try responseMessage(for: messageId, from: responseData) {
                                if responseTasks[messageId] != nil {
                                    responseTasks.removeValue(forKey: messageId)
                                    continuation.resume(returning: responseMessage)
                                }
                                return
                            }

                            if httpResponse.statusCode == 202 {
                                return // response will arrive over SSE
                            }

                            guard let responseMessage = try responseMessage(for: messageId, from: responseData) else {
                                let responseBody = String(data: responseData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                                let details = responseBody.isEmpty ? "" : ": \(responseBody)"
                                throw MCPServerProxyError.communicationError("HTTP 200 did not include JSON-RPC response for request \(messageId.stringValue)\(details)")
                            }

                            if responseTasks[messageId] != nil {
                                responseTasks.removeValue(forKey: messageId)
                                continuation.resume(returning: responseMessage)
                            }
                        default:
                            let responseBody = String(data: responseData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                            let details = responseBody.isEmpty ? "" : ": \(responseBody)"
                            throw MCPServerProxyError.communicationError("HTTP error \(httpResponse.statusCode)\(details)")
                        }
                    } catch {
                        if responseTasks[messageId] != nil {
                            responseTasks.removeValue(forKey: messageId)
                            continuation.resume(throwing: error)
                        }
                    }
                }
            }
        }
    }

    /// Sends a ping request to the server.
    public func ping() async throws {
        let requestId = nextRequestID()
        let request = JSONRPCMessage.request(id: requestId, method: "ping", params: nil)
        _ = try await send(request)
    }

    private func startLineConnection() async throws {
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

    // MARK: - Internal

    private func failPendingResponseTasks(with error: Error) {
        let pending = responseTasks
        responseTasks.removeAll()

        for (_, continuation) in pending {
            continuation.resume(throwing: error)
        }
    }

    private func handleStreamTermination(_ error: Error) {
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

    private func initialize() async throws {
        let requestId = nextRequestID()
        var params: [String: AnyCodable] = [
            "protocolVersion": AnyCodable("2025-06-18"),
            "clientInfo": AnyCodable([
                "name": "swiftmcp-client",
                "version": "1.0.0"
            ]),
            "capabilities": AnyCodable([:])
        ]
        
        // Add base metadata if present
        if !meta.isEmpty {
            params["_meta"] = AnyCodable(meta)
        }
        
        let request = JSONRPCMessage.request(id: requestId, method: "initialize", params: params)
        let response = try await send(request)

        guard case let .response(responseData) = response,
              let result = responseData.result else {
            throw MCPServerProxyError.communicationError("Invalid initialize response")
        }

        let rawServerDescription = extractServerDescription(from: result)
        let resultData = try JSONEncoder().encode(result)
        let initResult = try JSONDecoder().decode(InitializeResult.self, from: resultData)
        serverName = initResult.serverInfo.name
        serverVersion = initResult.serverInfo.version
        serverDescription = initResult.serverInfo.description ?? rawServerDescription
        serverCapabilities = initResult.capabilities
        if service == nil {
            service = serverName
        }
        logger.info("Connected to MCP server: \(serverName ?? "unknown") version \(serverVersion ?? "unknown")")
    }

    private func resolveTcpConfig(_ config: MCPServerTcpConfig) -> MCPServerTcpConfig {
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

    private func processIncomingMessage(event: String = "", data: String) async {
        if event == "endpoint" {
            if case .sse(let sseConfig) = config, isStreamableMCPURL(sseConfig.url) {
                // Ignore legacy endpoint events for streamable /mcp mode.
                return
            }
            if let url = URL(string: data) {
                endpointURL = url
                if let continuation = endpointContinuation {
                    endpointContinuation = nil
                    continuation.resume(returning: url)
                }
                return
            }
        }

        guard let jsonData = data.data(using: .utf8) else { return }
        logger.trace("[MCP DEBUG] Received JSON-RPC message: \(data)")
        let decoder = JSONDecoder()
        if let message = try? decoder.decode(JSONRPCMessage.self, from: jsonData) {
            switch message {
            case .request(let requestData):
                if requestData.method == "ping" {
                    logger.info("[MCP] Ping request received; sending response.")
                    await handlePingRequest(requestData)
                } else {
                    logger.debug("[MCP DEBUG] Ignoring client request: \(requestData.method)")
                }
            case .notification(let notification):
                await handleNotification(notification)
            case .response, .errorResponse:
                if let id = message.id, let waitingContinuation = responseTasks[id] {
                    responseTasks.removeValue(forKey: id)
                    waitingContinuation.resume(returning: message)
                } else {
                    logger.error("[MCP DEBUG] No waiting continuation found for ID \(message.id?.stringValue ?? "nil")")
                }
            }
        } else {
            logger.error("[MCP DEBUG] Failed to decode JSON-RPC message")
        }
    }

    func handleNotification(_ notification: JSONRPCMessage.JSONRPCNotificationData) async {
        if let handler = notificationHandlers[notification.method] {
            do {
                try await handler.handle(self, notification)
                return
            } catch {
                logger.error("[MCP] Failed to handle \(notification.method) as \(handler.payloadTypeDescription): \(String(describing: error))")
            }
        }

        handleUnhandledNotification(notification)
    }

    private func handlePingRequest(_ request: JSONRPCMessage.JSONRPCRequestData) async {
        guard let endpointURL = endpointURL else { return }
        guard case .sse(let sseConfig) = config else { return }
        let response = JSONRPCMessage.response(id: request.id, result: [:])
        let sessionConfig = URLSessionConfiguration.default
        let session = URLSession(configuration: sessionConfig)
        var urlRequest = URLRequest(url: endpointURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        configureSSEPOSTRequest(&urlRequest, sseConfig: sseConfig)
        let encoder = JSONEncoder()
        let data = try? encoder.encode(response)
        urlRequest.httpBody = data
        do {
            let (_, response) = try await session.data(for: urlRequest)
            if let httpResponse = response as? HTTPURLResponse, ![200, 202].contains(httpResponse.statusCode) {
                return
            }
        } catch {
            return
        }
    }

    private func handleUnhandledNotification(_ notification: JSONRPCMessage.JSONRPCNotificationData) {
        switch notification.method {
        case NotificationMethod.progress:
            logProgressNotification(notification)
        case NotificationMethod.log:
            logIncomingLogMessage(notification)
        default:
            logger.trace("[MCP DEBUG] Received notification: \(notification.method)")
        }
    }

    private func logProgressNotification(_ notification: JSONRPCMessage.JSONRPCNotificationData) {
        guard let params = notification.params else {
            logger.info("[MCP] Progress notification received.")
            return
        }
        let tokenValue = params["progressToken"]?.value
        let progressValue = numericValue(params["progress"]?.value)
        let totalValue = numericValue(params["total"]?.value)
        let messageValue = params["message"]?.value as? String

        var parts: [String] = []
        if let messageValue, !messageValue.isEmpty {
            parts.append(messageValue)
        }
        if let progressValue {
            if let percentText = progressPercentText(progressValue: progressValue, totalValue: totalValue) {
                parts.append("progress \(percentText)")
            } else if let totalValue {
                parts.append("progress \(progressValue)/\(totalValue)")
            } else {
                parts.append("progress \(progressValue)")
            }
        }
        if let tokenValue {
            parts.append("token \(tokenValue)")
        }

        if parts.isEmpty {
            logger.info("[MCP] Progress notification received.")
        } else {
            logger.info("[MCP] Progress: \(parts.joined(separator: " | "))")
        }
    }

    func handleLogNotification(_ notification: JSONRPCMessage.JSONRPCNotificationData) async {
        await handleNotification(notification)
    }

    private func updateLogNotificationRegistration() {
        guard let handler = logNotificationHandler else {
            removeNotificationHandler(for: NotificationMethod.log)
            return
        }

        notificationHandlers[NotificationMethod.log] = NotificationHandlerBox(
            payloadTypeDescription: String(reflecting: LogMessage.self),
            handle: { proxy, notification in
                let message = try Self.decodeNotificationPayload(from: notification, as: LogMessage.self)
                await handler.mcpServerProxy(proxy, didReceiveLog: message)
            }
        )
    }

    private func updateProgressNotificationRegistration() {
        guard let handler = progressNotificationHandler else {
            removeNotificationHandler(for: NotificationMethod.progress)
            return
        }

        notificationHandlers[NotificationMethod.progress] = NotificationHandlerBox(
            payloadTypeDescription: String(reflecting: ProgressNotification.self),
            handle: { proxy, notification in
                let progress = try Self.decodeNotificationPayload(from: notification, as: ProgressNotification.self)
                await handler.mcpServerProxy(proxy, didReceiveProgress: progress)
            }
        )
    }

    private static func decodeNotificationPayload<Payload>(
        from notification: JSONRPCMessage.JSONRPCNotificationData,
        as payloadType: Payload.Type = Payload.self
    ) throws -> Payload where Payload: Decodable {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let params = notification.params ?? [:]
        let data = try encoder.encode(params)
        return try decoder.decode(payloadType, from: data)
    }

    private func logIncomingLogMessage(_ message: LogMessage) {
        var parts: [String] = []
        parts.append("level \(message.level.rawValue)")
        if let loggerName = message.logger, !loggerName.isEmpty {
            parts.append("logger \(loggerName)")
        }
        let dataDescription = String(describing: message.data.value)
        if !dataDescription.isEmpty {
            parts.append("data \(dataDescription)")
        }

        let level = loggerLevel(for: message.level)
        if parts.isEmpty {
            logger.log(level: level, "[MCP] Log notification received.")
        } else {
            logger.log(level: level, "[MCP] Log: \(parts.joined(separator: " | "))")
        }
    }

    private func logIncomingLogMessage(_ notification: JSONRPCMessage.JSONRPCNotificationData) {
        guard let params = notification.params else {
            logger.info("[MCP] Log notification received.")
            return
        }

        let levelValue = params["level"]?.value as? String
        let level = levelValue.flatMap(LogLevel.init(string:)) ?? .info
        let loggerName = params["logger"]?.value as? String
        let dataValue = params["data"] ?? AnyCodable("")
        let message = LogMessage(level: level, logger: loggerName, data: dataValue)
        logIncomingLogMessage(message)
    }

    private func loggerLevel(for level: LogLevel) -> Logger.Level {
        switch level {
        case .debug:
            return .debug
        case .info:
            return .info
        case .notice:
            return .notice
        case .warning:
            return .warning
        case .error:
            return .error
        case .critical, .alert, .emergency:
            return .critical
        }
    }

    private func numericValue(_ value: Any?) -> Double? {
        switch value {
        case let double as Double:
            return double
        case let int as Int:
            return Double(int)
        case let int64 as Int64:
            return Double(int64)
        case let uint as UInt:
            return Double(uint)
        case let float as Float:
            return Double(float)
        default:
            return nil
        }
    }

    private func extractTextPayload(from contentArray: [Any]) -> String? {
        guard contentArray.count == 1 else {
            return nil
        }
        for content in contentArray {
            guard let contentDict = contentDictionary(from: content),
                  let type = stringValue(contentDict["type"]),
                  type == "text",
                  let text = stringValue(contentDict["text"]) else {
                continue
            }
            return text
        }
        return nil
    }

    private func encodeContentPayload(from contentArray: [Any]) -> String? {
        let normalized = contentArray.compactMap { contentDictionary(from: $0) }
        if normalized.isEmpty {
            return "[]"
        }
        let payload: Any = normalized.count == 1 ? normalized[0] : normalized
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }

    private func contentDictionary(from value: Any?) -> [String: Any]? {
        if let dict = value as? [String: Any] {
            return dict
        }
        if let dict = value as? [String: AnyCodable] {
            return dict.mapValues { $0.value }
        }
        if let anyCodable = value as? AnyCodable {
            return contentDictionary(from: anyCodable.value)
        }
        return nil
    }

    private func stringValue(_ value: Any?) -> String? {
        if let string = value as? String {
            return string
        }
        if let anyCodable = value as? AnyCodable {
            return stringValue(anyCodable.value)
        }
        return nil
    }

    private func requestResult(
        method: String,
        params: [String: AnyCodable]? = nil
    ) async throws -> [String: AnyCodable] {
        let requestId = nextRequestID()
        var requestParams = params ?? [:]

        if !meta.isEmpty {
            var requestMeta = meta
            if let existingMeta = requestParams["_meta"]?.value as? [String: AnyCodable] {
                requestMeta.merge(existingMeta) { _, new in new }
            } else if let existingMeta = requestParams["_meta"]?.value as? [String: Any] {
                for (key, value) in existingMeta {
                    requestMeta[key] = AnyCodable(value)
                }
            }
            requestParams["_meta"] = AnyCodable(requestMeta)
        }

        let request = JSONRPCMessage.request(id: requestId, method: method, params: requestParams.isEmpty ? nil : requestParams)
        let response = try await send(request)

        switch response {
        case .response(let responseData):
            guard let result = responseData.result else {
                throw MCPServerProxyError.communicationError("Invalid response type for \(method)")
            }
            if let isError = result["isError"]?.value as? Bool, isError {
                throw MCPServerProxyError.communicationError(errorMessage(from: result) ?? "Request failed for \(method)")
            }
            return result
        case .errorResponse(let errorResponse):
            throw MCPServerProxyError.communicationError(errorResponse.error.message)
        default:
            throw MCPServerProxyError.communicationError("Invalid response type for \(method)")
        }
    }

    private func decodeResultField<T: Decodable>(
        _ field: String,
        from result: [String: AnyCodable],
        method: String,
        as type: T.Type = T.self
    ) throws -> T {
        let value: AnyCodable
        if field == "self" {
            value = AnyCodable(result)
        } else if let fieldValue = result[field] {
            value = fieldValue
        } else {
            throw MCPServerProxyError.communicationError("Invalid response format for \(method)")
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601WithTimeZone
        let data = try encoder.encode(value)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601WithTimeZone
        return try decoder.decode(type, from: data)
    }

    private func errorMessage(from result: [String: AnyCodable]) -> String? {
        if let message = stringValue(result["message"]) {
            return message
        }
        if let contentValue = result["content"]?.value {
            let contentArray: [Any]
            if let array = contentValue as? [Any] {
                contentArray = array
            } else if let array = contentValue as? [AnyCodable] {
                contentArray = array.map(\.value)
            } else {
                contentArray = []
            }
            return extractTextPayload(from: contentArray)
        }
        return nil
    }


    private func extractServerDescription(from result: [String: AnyCodable]) -> String? {
        guard let serverInfoValue = result["serverInfo"]?.value else {
            return nil
        }
        if let info = serverInfoValue as? [String: AnyCodable] {
            return info["description"]?.value as? String
        }
        if let info = serverInfoValue as? [String: Any] {
            return info["description"] as? String
        }
        return nil
    }

    private func progressPercentText(progressValue: Double, totalValue: Double?) -> String? {
        if let totalValue, totalValue > 0 {
            return formatPercent((progressValue / totalValue) * 100)
        }
        if progressValue >= 0, progressValue <= 1 {
            return formatPercent(progressValue * 100)
        }
        return nil
    }

    private func formatPercent(_ percent: Double) -> String {
        let rounded = Int(percent.rounded())
        return "\(rounded)%"
    }

    private func isStreamableMCPURL(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false
        }
        return components.path.hasPrefix("/mcp")
    }

    private func applyConfiguredSSEHeaders(_ request: inout URLRequest, sseConfig: MCPServerSseConfig) {
        for (key, value) in sseConfig.headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        // Allow token in metadata to override auth header from config.
        if let accessToken = meta["accessToken"]?.value as? String {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
    }

    private func configureSSEPOSTRequest(_ request: inout URLRequest, sseConfig: MCPServerSseConfig) {
        applyConfiguredSSEHeaders(&request, sseConfig: sseConfig)
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")

        if let sessionID {
            request.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id")
        }
    }

    private func responseMessage(for requestID: JSONRPCID, from data: Data) throws -> JSONRPCMessage? {
        guard !data.isEmpty else {
            return nil
        }

        let messages = try JSONRPCMessage.decodeMessages(from: data)
        return messages.first { message in
            guard message.id == requestID else {
                return false
            }
            switch message {
            case .response, .errorResponse:
                return true
            case .request, .notification:
                return false
            }
        }
    }

    // MARK: - SSE Connection (Apple platforms)

    #if !os(Linux)
    @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, macCatalyst 15.0, *)
    private func connectSSEApple(sseConfig: MCPServerSseConfig) async throws {
        let isStreamableMCP = isStreamableMCPURL(sseConfig.url)
        if isStreamableMCP {
            endpointURL = sseConfig.url
        }

        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = .infinity
        sessionConfig.timeoutIntervalForResource = .infinity

        let session = URLSession(configuration: sessionConfig)
        var request = URLRequest(url: sseConfig.url)
        request.httpMethod = "GET"
        applyConfiguredSSEHeaders(&request, sseConfig: sseConfig)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        streamTask = Task {
            do {
                let (asyncBytes, response) = try await session.bytes(for: request)
                try self.handleSSEResponse(response, sseConfig: sseConfig, isStreamableMCP: isStreamableMCP)

                for try await message in asyncBytes.lines.sseMessages() {
                    await self.processIncomingMessage(event: message.event, data: message.data)
                }
                self.handleStreamTermination(
                    MCPServerProxyError.communicationError(
                        "SSE stream closed by server before response was received"
                    )
                )
            } catch is CancellationError {
                // Pending requests are cancelled in disconnect().
            } catch {
                self.logger.error("[MCP DEBUG] SSE stream error: \(error)")
                self.handleStreamTermination(error)
            }
        }

        try await waitForEndpointIfNeeded(isStreamableMCP: isStreamableMCP)
        try await initialize()
    }
    #endif

    // MARK: - SSE Connection (Linux)

    #if os(Linux)
    private func connectSSELinux(sseConfig: MCPServerSseConfig) async throws {
        let isStreamableMCP = isStreamableMCPURL(sseConfig.url)
        if isStreamableMCP {
            endpointURL = sseConfig.url
        }

        let sessionConfig = URLSessionConfiguration.default

        var request = URLRequest(url: sseConfig.url)
        request.httpMethod = "GET"
        applyConfiguredSSEHeaders(&request, sseConfig: sseConfig)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        // Use a streaming delegate since URLSession.bytes is unavailable on Linux
        let proxy = self
        let delegate = SSEStreamingDelegate { response in
            Task {
                await proxy.handleSSEResponse(response, sseConfig: sseConfig, isStreamableMCP: isStreamableMCP)
            }
        }

        let session = URLSession(configuration: sessionConfig, delegate: delegate, delegateQueue: nil)
        let task = session.dataTask(with: request)
        task.resume()

        streamTask = Task {
            do {
                for try await message in delegate.lines.sseMessages() {
                    await self.processIncomingMessage(event: message.event, data: message.data)
                }
                self.handleStreamTermination(
                    MCPServerProxyError.communicationError(
                        "SSE stream closed by server before response was received"
                    )
                )
            } catch is CancellationError {
                task.cancel()
            } catch {
                self.logger.error("[MCP DEBUG] SSE stream error: \(error)")
                self.handleStreamTermination(error)
            }
        }

        try await waitForEndpointIfNeeded(isStreamableMCP: isStreamableMCP)
        try await initialize()
    }
    #endif

    // MARK: - Shared SSE Helpers

    private func handleSSEResponse(_ response: URLResponse, sseConfig: MCPServerSseConfig, isStreamableMCP: Bool) {
        if let httpResponse = response as? HTTPURLResponse {
            sessionID = httpResponse.value(forHTTPHeaderField: "Mcp-Session-Id")
            if isStreamableMCP {
                endpointURL = sseConfig.url
            } else if let sessionID,
                      let endpoint = messageEndpointURL(baseURL: sseConfig.url, sessionId: sessionID) {
                endpointURL = endpoint
            }
        }
    }

    private func waitForEndpointIfNeeded(isStreamableMCP: Bool) async throws {
        if !isStreamableMCP && endpointURL == nil {
            let _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
                self.endpointContinuation = continuation

                Task {
                    try await Task.sleep(nanoseconds: 10_000_000_000)
                    if let cont = self.endpointContinuation {
                        self.endpointContinuation = nil
                        cont.resume(throwing: MCPServerProxyError.communicationError("Timeout waiting for endpoint URL"))
                    }
                }
            }
        }
    }

    private func messageEndpointURL(baseURL: URL, sessionId: String) -> URL? {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.path = "/messages/\(sessionId)"
        return components.url
    }
}

private extension JSONRPCID {
    var stringValue: String {
        switch self {
        case .int(let value):
            return String(value)
        case .string(let value):
            return value
        }
    }
}
