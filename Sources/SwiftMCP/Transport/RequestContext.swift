import Foundation
import AnyCodable

/// Represents the context of a single JSON-RPC message.
///
/// A context tracks the message identifier, method name and optional
/// metadata like a progress token. It is stored in task local storage so
/// it can be accessed from anywhere while handling the message.
public final class RequestContext: @unchecked Sendable {
    /// Additional metadata sent in the `_meta` field of a request.
    public struct Meta: @unchecked Sendable {
        /// Optional progress token for sending progress notifications.
        public let progressToken: AnyCodable?

        init?(dictionary: [String: Any]) {
            if let token = dictionary["progressToken"] {
                self.progressToken = AnyCodable(token)
            } else {
                self.progressToken = nil
            }
        }
    }

    /// The identifier of the JSON-RPC message.
    public let id: JSONRPCID?
    /// The method of the JSON-RPC message if applicable.
    public let method: String?
    /// Optional metadata for the message.
    public let meta: Meta?

    /// Creates a new request context for the given message.
    public init(message: JSONRPCMessage) {
        switch message {
        case .request(let data):
            id = data.id
            method = data.method
            if let params = data.params,
               let dict = params["_meta"]?.value as? [String: Any] {
                meta = Meta(dictionary: dict)
            } else {
                meta = nil
            }
        case .notification(let data):
            id = nil
            method = data.method
            if let params = data.params,
               let dict = params["_meta"]?.value as? [String: Any] {
                meta = Meta(dictionary: dict)
            } else {
                meta = nil
            }
        case .response(let data):
            id = data.id
            method = nil
            meta = nil
        case .errorResponse(let data):
            id = data.id
            method = nil
            meta = nil
        }
    }

    @TaskLocal
    private static var taskContext: RequestContext?

    /// Accessor for the current context stored in task local storage.
    public static var current: RequestContext! { taskContext }

    /// Runs `operation` with this context bound to `RequestContext.current`.
    public func work<T>(_ operation: (RequestContext) async throws -> T) async rethrows -> T {
        try await Self.$taskContext.withValue(self) {
            try await operation(self)
        }
    }

    /// Send a progress notification if a progress token was provided.
    public func reportProgress(_ progress: Double, total: Double? = nil, message: String? = nil) async {
        guard let progressToken = meta?.progressToken else { return }
        
        await Session.current?.sendProgressNotification(progressToken: progressToken,
                                                        progress: progress,
                                                        total: total,
                                                        message: message)
    }

    /// Notify the client that the list of available tools changed.
    public func sendToolListChanged() async {
        await Session.current?.sendToolListChanged()
    }

    /// Notify the client that the list of available resources changed.
    public func sendResourceListChanged() async {
        await Session.current?.sendResourceListChanged()
    }

    /// Notify the client that the list of available prompts changed.
    public func sendPromptListChanged() async {
        await Session.current?.sendPromptListChanged()
    }

    /// Request sampling from the client.
    ///
    /// This method sends a sampling request to the client and returns the generated response.
    /// The client is responsible for model selection, user approval, and actual LLM generation.
    ///
    /// - Parameter request: The sampling request containing messages and preferences
    /// - Returns: The generated sampling response
    /// - Throws: An error if the sampling request fails
    public func sample(_ request: SamplingCreateMessageRequest) async throws -> SamplingCreateMessageResponse {
        guard let session = Session.current else {
            throw MCPServerError.noActiveSession
        }
        
        // Check if client supports sampling  
        guard await session.clientCapabilities?.sampling != nil else {
            throw MCPServerError.clientHasNoSamplingSupport
        }
        
        // Encode the request parameters
        let encoder = DictionaryEncoder()
        let params = try encoder.encode(request)
        
        // Send the sampling request to the client
        let response = try await session.request(method: "sampling/createMessage", params: params)
        
        // Check for error responses from the client
        if case .errorResponse(let errorData) = response {
            throw MCPServerError.clientError(code: errorData.error.code, message: errorData.error.message)
        }
        
        // Parse the response
        guard case .response(let responseData) = response,
              let result = responseData.result else {
            throw MCPServerError.unexpectedMessageType(method: "sampling/createMessage")
        }
        
        // Convert AnyCodable dictionary to [String: Any] for decoding
        let resultDict = result.mapValues { $0.value }
        
        // Decode the response using the Dictionary extension
        return try resultDict.decode(SamplingCreateMessageResponse.self)
    }
    
    /// Convenience method for simple text sampling.
    ///
    /// - Parameters:
    ///   - prompt: The text prompt to send
    ///   - systemPrompt: Optional system prompt
    ///   - modelPreferences: Optional model preferences
    ///   - maxTokens: Optional maximum tokens to generate (defaults to 1000)
    /// - Returns: The generated text response
    /// - Throws: An error if the sampling request fails
    public func sample(
        prompt: String,
        systemPrompt: String? = nil,
        modelPreferences: ModelPreferences? = nil,
        maxTokens: Int? = 1000
    ) async throws -> String {
        let message = SamplingMessage(
            role: .user,
            content: SamplingContent(text: prompt)
        )
        
        let request = SamplingCreateMessageRequest(
            messages: [message],
            modelPreferences: modelPreferences,
            systemPrompt: systemPrompt,
            maxTokens: maxTokens
        )
        
        let response = try await sample(request)
        
        // Extract text content from response
        guard response.content.type == .text,
              let text = response.content.text else {
            throw MCPToolError.unknownTool(name: "sampling/createMessage")
        }
        
        return text
    }
    
    /// Request information from the user through the client.
    ///
    /// This method sends an elicitation request to the client asking for structured user input.
    /// The client is responsible for presenting the request to the user and validating their response.
    ///
    /// - Parameter request: The elicitation request containing message and schema
    /// - Returns: The elicitation response with user action and optional content
    /// - Throws: An error if the elicitation request fails
    public func elicit(_ request: ElicitationCreateRequest) async throws -> ElicitationCreateResponse {
        guard let session = Session.current else {
            throw MCPServerError.noActiveSession
        }
        
        // Check if client supports elicitation
        let capabilities = await session.clientCapabilities
        print("DEBUG: Client capabilities: \(String(describing: capabilities))")
        print("DEBUG: Elicitation support: \(String(describing: capabilities?.elicitation))")
        guard capabilities?.elicitation != nil else {
            throw MCPServerError.clientHasNoElicitationSupport
        }
        
        // Encode the request parameters
        let encoder = DictionaryEncoder()
        let params = try encoder.encode(request)
        
        // Debug: Print the encoded parameters
        print("DEBUG: Encoded elicitation params: \(params)")
        
        // Send the elicitation request to the client
        let response = try await session.request(method: "elicitation/create", params: params)
        
        // Check for error responses from the client
        if case .errorResponse(let errorData) = response {
            throw MCPServerError.clientError(code: errorData.error.code, message: errorData.error.message)
        }
        
        // Parse the response
        guard case .response(let responseData) = response,
              let result = responseData.result else {
            throw MCPServerError.unexpectedMessageType(method: "elicitation/create")
        }
        
        // Convert AnyCodable dictionary to [String: Any] for decoding
        let resultDict = result.mapValues { $0.value }
        
        // Decode the response using the Dictionary extension
        return try resultDict.decode(ElicitationCreateResponse.self)
    }
    
    /// Convenience method for simple elicitation with basic schema.
    ///
    /// - Parameters:
    ///   - message: The message explaining what information is being requested
    ///   - schema: The JSON schema defining the expected response structure
    /// - Returns: The elicitation response with user action and optional content
    /// - Throws: An error if the elicitation request fails
    public func elicit(message: String, schema: JSONSchema) async throws -> ElicitationCreateResponse {
        let request = ElicitationCreateRequest(message: message, requestedSchema: schema)
        return try await elicit(request)
    }
}
