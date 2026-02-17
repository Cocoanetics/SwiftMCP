import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import AnyCodable
import Logging

/// A proxy for interacting with an MCP server over stdio, TCP, or SSE.
public final actor MCPServerProxy: Sendable {
    public let logger = Logger(label: "com.cocoanetics.SwiftMCP.MCPServerProxy")

    /// The configuration for the MCP server.
    public let config: MCPServerConfig

    /// Optional Bonjour service name to prefer during discovery.
    public var service: String?

    /// Specifies whether the list of tools from the server should be cached.
    public let cacheToolsList: Bool

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
    private var streamTask: Task<Void, Error>?

    public private(set) var serverName: String?
    public private(set) var serverVersion: String?
    public private(set) var serverDescription: String?
    public private(set) var serverCapabilities: ServerCapabilities?

    /// Optional handler for log notifications from the server.
    public var logNotificationHandler: (any MCPServerProxyLogNotificationHandling)?

    /// Updates the log notification handler.
    public func setLogNotificationHandler(_ handler: (any MCPServerProxyLogNotificationHandling)?) {
        logNotificationHandler = handler
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
                throw MCPServerProxyError.unsupportedPlatform("SSE client connections require URLSession.bytes support on Linux.")
#else
                if #available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, macCatalyst 15.0, *) {
                    let sessionConfig = URLSessionConfiguration.default
                    sessionConfig.timeoutIntervalForRequest = .infinity
                    sessionConfig.timeoutIntervalForResource = .infinity

                    let session = URLSession(configuration: sessionConfig)
                    var request = URLRequest(url: sseConfig.url)
                    request.httpMethod = "GET"
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

                    for (key, value) in sseConfig.headers {
                        request.setValue(value, forHTTPHeaderField: key)
                    }

                    let (asyncBytes, response) = try await session.bytes(for: request)

                    if let response = response as? HTTPURLResponse, response.statusCode != 200 {
                        let data = try await asyncBytes.reduce(into: Data()) { partialResult, byte in
                            partialResult.append(byte)
                        }
                        throw MCPServerProxyError.communicationError("HTTP error \(response.statusCode): \(String(data: data, encoding: .utf8) ?? "Unknown error")")
                    }

                    if let response = response as? HTTPURLResponse,
                       let sessionId = response.value(forHTTPHeaderField: "Mcp-Session-Id"),
                       let endpoint = messageEndpointURL(baseURL: sseConfig.url, sessionId: sessionId) {
                        endpointURL = endpoint
                    }

                    streamTask = Task {
                        do {
                            for try await message in asyncBytes.lines.sseMessages() {
                                processIncomingMessage(event: message.event, data: message.data)
                            }
                            self.handleStreamTermination(
                                MCPServerProxyError.communicationError(
                                    "SSE stream closed by server before response was received"
                                )
                            )
                        } catch is CancellationError {
                            // Pending requests are cancelled in disconnect().
                        } catch {
                            logger.error("[MCP DEBUG] SSE stream error: \(error)")
                            self.handleStreamTermination(error)
                        }
                    }

                    if endpointURL == nil {
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

                    try await initialize()
                } else {
                    throw MCPServerProxyError.unsupportedPlatform("SSE client connections require newer OS availability.")
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

        let requestId = nextRequestID()
        let request = JSONRPCMessage.request(id: requestId, method: "tools/list")
        let response = try await send(request)

        guard case let .response(respData) = response, let result = respData.result else {
            throw MCPServerProxyError.communicationError("Invalid response type for tools/list")
        }

        if let isError = result["isError"]?.value as? Bool, isError {
            throw MCPServerProxyError.communicationError("Server does not provide any tools")
        }

        guard let toolsData = result["tools"]?.value as? [[String: Any]] else {
            throw MCPServerProxyError.communicationError("Invalid response format for tools/list")
        }

        let tools = try toolsData.compactMap { toolData -> MCPTool? in
            guard let name = toolData["name"] as? String,
                  let inputSchema = toolData["inputSchema"] as? [String: Any] else {
                return nil
            }

            let description = toolData["description"] as? String
            let schema = try JSONDecoder().decode(JSONSchema.self, from: JSONSerialization.data(withJSONObject: inputSchema))
            let outputSchema: JSONSchema?
            if let outputSchemaData = toolData["outputSchema"] as? [String: Any] {
                outputSchema = try JSONDecoder().decode(JSONSchema.self, from: JSONSerialization.data(withJSONObject: outputSchemaData))
            } else {
                outputSchema = nil
            }

            // Parse annotations if present
            let annotations: MCPToolAnnotations?
            if let annotationsData = toolData["annotations"] as? [String: Any] {
                annotations = try JSONDecoder().decode(MCPToolAnnotations.self, from: JSONSerialization.data(withJSONObject: annotationsData))
            } else {
                annotations = nil
            }

            return MCPTool(name: name, description: description, inputSchema: schema, outputSchema: outputSchema, annotations: annotations)
        }

        if cacheToolsList {
            cachedTools = tools
        }

        return tools
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
        if let progressToken {
            params["_meta"] = AnyCodable(["progressToken": progressToken])
        }
        let request = JSONRPCMessage.request(id: requestId, method: "tools/call", params: params)
        let responseMessage = try await send(request)

        guard case let .response(responseData) = responseMessage, let result = responseData.result else {
            throw MCPServerProxyError.communicationError("Invalid response type for tools/call, expected JSONRPCResponse")
        }

        if let isError = result["isError"]?.value as? Bool, isError {
            var errorMessage = "Tool call failed with an unspecified error."
            if let contentArray = result["content"]?.value as? [Any],
               let firstContent = contentArray.first as? [String: Any],
               let text = firstContent["text"] as? String {
                errorMessage = text
            }
            throw MCPServerProxyError.toolError(errorMessage)
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

        case .sse:
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
                        let (_, response) = try await session.data(for: urlRequest)
                        if let httpResponse = response as? HTTPURLResponse,
                           ![200, 202].contains(httpResponse.statusCode) {
                            if responseTasks[messageId] != nil {
                                responseTasks.removeValue(forKey: messageId)
                                continuation.resume(throwing: MCPServerProxyError.communicationError("HTTP error \(httpResponse.statusCode)"))
                            }
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
                    processIncomingMessage(data: data)
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
        let params: [String: AnyCodable] = [
            "protocolVersion": AnyCodable("2025-06-18"),
            "clientInfo": AnyCodable([
                "name": "swiftmcp-client",
                "version": "1.0.0"
            ]),
            "capabilities": AnyCodable([:])
        ]
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

    private func processIncomingMessage(event: String = "", data: String) {
        Task {
            if event == "endpoint" {
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
                    if notification.method == "notifications/progress" {
                        logProgressNotification(notification)
                    } else if notification.method == "notifications/message" {
                        await handleLogNotification(notification)
                    } else {
                        logger.trace("[MCP DEBUG] Received notification: \(notification.method)")
                    }
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
    }

    private func handlePingRequest(_ request: JSONRPCMessage.JSONRPCRequestData) async {
        guard let endpointURL = endpointURL else { return }
        let response = JSONRPCMessage.response(id: request.id, result: [:])
        let sessionConfig = URLSessionConfiguration.default
        let session = URLSession(configuration: sessionConfig)
        var urlRequest = URLRequest(url: endpointURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
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
        guard let params = notification.params else {
            logger.info("[MCP] Log notification received.")
            return
        }

        let levelValue = params["level"]?.value as? String
        let level = levelValue.flatMap(LogLevel.init(string:)) ?? .info
        let loggerName = params["logger"]?.value as? String
        let dataValue = params["data"] ?? AnyCodable("")
        let message = LogMessage(level: level, logger: loggerName, data: dataValue)

        if let handler = logNotificationHandler {
            await handler.mcpServerProxy(self, didReceiveLog: message)
        } else {
            logIncomingLogMessage(message)
        }
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
