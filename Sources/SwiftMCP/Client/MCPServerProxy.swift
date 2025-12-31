import Foundation
import AnyCodable
import Logging

/// A proxy for interacting with an MCP server over stdio or SSE.
public final actor MCPServerProxy: Sendable {
    public let logger = Logger(label: "com.cocoanetics.SwiftMCP.MCPServerProxy")

    /// The configuration for the MCP server.
    public let config: MCPServerConfig

    /// Specifies whether the list of tools from the server should be cached.
    public let cacheToolsList: Bool

    private var cachedTools: [MCPTool]?
    private var requestIdSequence: Int = 0

    private func nextRequestID() -> JSONRPCID {
        defer { requestIdSequence += 1 }
        return .int(requestIdSequence)
    }

    private var responseTasks: [JSONRPCID: CheckedContinuation<JSONRPCMessage, Error>] = [:]

    public private(set) var endpointURL: URL?
    private var streamTask: Task<Void, Error>?

    public private(set) var serverName: String?
    public private(set) var serverVersion: String?
    public private(set) var serverCapabilities: ServerCapabilities?

    private var stdioConnection: (any StdioConnection)?
    private var endpointContinuation: CheckedContinuation<URL, Error>?

    public init(config: MCPServerConfig, cacheToolsList: Bool = false) {
        self.config = config
        self.cacheToolsList = cacheToolsList
    }

    /// Connects to the MCP server and establishes an SSE or stdio connection.
    public func connect() async throws {
        switch config {
            case .stdio(let stdioConfig):
                stdioConnection = MCPServerProcess(config: stdioConfig)
                try await startStdioConnection()
                try await initialize()

            case .stdioHandles(let server):
                stdioConnection = InProcessStdioBridge(server: server)
                try await startStdioConnection()
                try await initialize()

            case .sse(let sseConfig):
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
                        } catch {
                            logger.error("[MCP DEBUG] SSE stream error: \(error)")
                            endpointContinuation?.resume(throwing: error)
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
        }
    }

    /// Disconnects from the MCP server.
    public func disconnect() async {
        switch config {
        case .stdio, .stdioHandles:
            await stdioConnection?.stop()
            stdioConnection = nil
        case .sse:
            break
        }
        streamTask?.cancel()
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

            return MCPTool(name: name, description: description, inputSchema: schema)
        }

        if cacheToolsList {
            cachedTools = tools
        }

        return tools
    }

    /// Calls a tool by name on the connected MCP server with the provided arguments.
    public func callTool(_ name: String, arguments: [String: any Sendable] = [:]) async throws -> String {
        let requestId = nextRequestID()
        let encodableArguments = arguments.mapValues { AnyCodable($0) }
        let params: [String: AnyCodable] = [
            "name": AnyCodable(name),
            "arguments": AnyCodable(encodableArguments)
        ]
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
            throw MCPServerProxyError.communicationError(errorMessage)
        }

        guard let contentArray = result["content"]?.value as? [Any] else {
            throw MCPServerProxyError.communicationError("Invalid content format in tools/call response")
        }

        if let firstContent = contentArray.first as? [String: Any],
           let type = firstContent["type"] as? String,
           type == "text",
           let text = firstContent["text"] as? String {
            return text
        }

        do {
            let jsonData = try JSONEncoder().encode(result)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                return jsonString
            }
        } catch {
            throw MCPServerProxyError.communicationError("Failed to encode result as JSON: \(error.localizedDescription)")
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
        case .stdio, .stdioHandles:
            guard let messageId = messageId else {
                throw MCPServerProxyError.communicationError("Message must have an ID")
            }
            let encoder = JSONEncoder()
            let data = try encoder.encode(message)

            let messageWithNewline = data + "\n".data(using: .utf8)!
            guard let stdioConnection else {
                throw MCPServerProxyError.communicationError("Not connected to stdio server")
            }
            await stdioConnection.write(messageWithNewline)

            return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<JSONRPCMessage, Error>) in
                responseTasks[messageId] = continuation
            }

        case .sse:
            guard let endpointURL = endpointURL else {
                throw MCPServerProxyError.communicationError("Not connected to server")
            }
            guard let messageId = messageId else {
                throw MCPServerProxyError.communicationError("Message must have an ID")
            }
            let session = URLSession(configuration: .default)
            var urlRequest = URLRequest(url: endpointURL)
            urlRequest.httpMethod = "POST"
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let encoder = JSONEncoder()
            let data = try encoder.encode(message)
            urlRequest.httpBody = data

            return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<JSONRPCMessage, Error>) in
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

    private func startStdioConnection() async throws {
        guard let stdioConnection else {
            throw MCPServerProxyError.communicationError("Not connected to stdio server")
        }
        try await stdioConnection.start()

        streamTask = Task {
            do {
                let lines = await stdioConnection.lines()
                for try await data in lines {
                    processIncomingMessage(data: data)
                }
            } catch {
                logger.error("[MCP DEBUG] Stream error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Internal

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

        let resultData = try JSONEncoder().encode(result)
        let initResult = try JSONDecoder().decode(InitializeResult.self, from: resultData)
        serverName = initResult.serverInfo.name
        serverVersion = initResult.serverInfo.version
        serverCapabilities = initResult.capabilities
        logger.info("Connected to MCP server: \(serverName ?? "unknown") version \(serverVersion ?? "unknown")")
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
                        await handlePingRequest(requestData)
                    }
                case .response, .errorResponse:
                    if let id = message.id, let waitingContinuation = responseTasks[id] {
                        responseTasks.removeValue(forKey: id)
                        waitingContinuation.resume(returning: message)
                    } else {
                        logger.error("[MCP DEBUG] No waiting continuation found for ID \(message.id?.stringValue ?? "nil")")
                    }
                default:
                    logger.error("[MCP DEBUG] Unhandled JSON-RPC message type")
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
