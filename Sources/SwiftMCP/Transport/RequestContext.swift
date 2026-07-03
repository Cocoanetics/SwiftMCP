//
//  RequestContext.swift
//  SwiftMCP
//
//  Part of the always-on server runtime (not behind the `Server` trait). The
//  core `MCPServer` request-dispatch layer binds and reads
//  `RequestContext.current`, so this type must compile without swift-nio.
//

import Foundation

/// Represents the context of a single JSON-RPC message.
///
/// A context tracks the message identifier, method name and optional
/// metadata like a progress token. It is stored in task local storage so
/// it can be accessed from anywhere while handling the message.
public final class RequestContext: Sendable {
    /// Additional metadata sent in the `_meta` field of a request.
    public struct Meta: Sendable {
        /// Optional progress token for sending progress notifications.
        public let progressToken: JSONValue?

        /// Optional authentication token for authorization.
        public let accessToken: String?

        /// The protocol revision this request declares (modern `2026-07-28`+),
        /// from `io.modelcontextprotocol/protocolVersion`.
        public let protocolVersion: String?

        /// The client software identity, from `io.modelcontextprotocol/clientInfo`.
        public let clientInfo: Implementation?

        /// The client's declared capabilities, from `io.modelcontextprotocol/clientCapabilities`.
        public let clientCapabilities: ClientCapabilities?

        /// The log level requested for this request, from `io.modelcontextprotocol/logLevel`.
        public let logLevel: LogLevel?

        init?(dictionary: JSONDictionary) {
            if dictionary.isEmpty {
                return nil
            }

            self.progressToken = dictionary["progressToken"]
            self.accessToken = dictionary["accessToken"]?.stringValue

            // Modern per-request identity. Best-effort: malformed metadata is
            // treated as absent rather than failing the whole request.
            self.protocolVersion = dictionary[MCPMetaKey.protocolVersion]?.stringValue
            self.clientInfo = try? dictionary[MCPMetaKey.clientInfo]?.decoded(Implementation.self)
            self.clientCapabilities = try? dictionary[MCPMetaKey.clientCapabilities]?.decoded(ClientCapabilities.self)
            self.logLevel = dictionary[MCPMetaKey.logLevel]?.stringValue.flatMap(LogLevel.init(string:))
        }
    }

    /// The identifier of the JSON-RPC message.
    public let id: JSONRPCID?
    /// The method of the JSON-RPC message if applicable.
    public let method: String?
    /// Optional metadata for the message.
    public let meta: Meta?

    /// The raw `params.inputResponses` from an MRTR retry (modern, 2026-07-28).
    public let inputResponses: JSONDictionary?
    /// The opaque `params.requestState` echoed by an MRTR retry.
    public let requestState: String?

    /// Per-execution MRTR bookkeeping: the merged input responses the era-aware
    /// `sample`/`elicit`/`listRoots` consult, and the ordinal counter that gives
    /// each call site a deterministic id across re-executions.
    let mrtr = MRTRExecutionState()

    /// Creates a new request context for the given message.
    public init(message: JSONRPCMessage) {
        switch message {
        case .request(let data):
            id = data.id
            method = data.method
            if let params = data.params,
               let dict = params["_meta"]?.dictionaryValue {
                meta = Meta(dictionary: dict)
            } else {
                meta = nil
            }
            inputResponses = data.params?["inputResponses"]?.dictionaryValue
            requestState = data.params?["requestState"]?.stringValue
        case .notification(let data):
            id = nil
            method = data.method
            if let params = data.params,
               let dict = params["_meta"]?.dictionaryValue {
                meta = Meta(dictionary: dict)
            } else {
                meta = nil
            }
            inputResponses = nil
            requestState = nil
        case .response(let data):
            id = data.id
            method = nil
            meta = nil
            inputResponses = nil
            requestState = nil
        case .errorResponse(let data):
            id = data.id
            method = nil
            meta = nil
            inputResponses = nil
            requestState = nil
        }
    }

    @TaskLocal
    internal static var taskContext: RequestContext?

    /// Mutable MRTR execution state, isolated in an actor so the Sendable
    /// context can carry it. The ordinal counter makes each `sample`/`elicit`/
    /// `listRoots` call site yield the same id (`input-N`) on every re-execution
    /// of the handler, so a retry's responses land at the right call sites.
    actor MRTRExecutionState {
        private var ordinal = 0
        private var responses: [String: JSONValue] = [:]

        /// Installs the merged response map (signed-state accumulator ∪ the
        /// retry's `inputResponses`) before the handler runs.
        func setResponses(_ merged: [String: JSONValue]) {
            responses = merged
        }

        /// The next deterministic input id.
        func nextOrdinalID() -> String {
            defer { ordinal += 1 }
            return "input-\(ordinal)"
        }

        func response(for id: String) -> JSONValue? {
            responses[id]
        }

        func allResponses() -> [String: JSONValue] {
            responses
        }
    }

    /// Accessor for the current context stored in task local storage.
    public static var current: RequestContext! { taskContext }

    /// Runs `operation` with this context bound to `RequestContext.current`.
    public func work<T>(_ operation: (RequestContext) async throws -> T) async rethrows -> T {
        try await Self.$taskContext.withValue(self) {
            try await operation(self)
        }
    }

    /// MRTR resolution for a modern server→client input request: the call site
    /// takes its deterministic ordinal id; when the retry (or the signed-state
    /// accumulator) already carries the answer it is returned immediately,
    /// otherwise ``InputRequiredSignal`` aborts the handler so the dispatcher
    /// can reply `input_required`. On the client's retry the handler re-runs and
    /// the same call site finds its answer under the same id.
    ///
    /// - Important: MRTR re-executes the handler from scratch on every retry, so
    ///   a handler's *sequence* of `sample`/`elicit`/`listRoots` calls must be
    ///   deterministic with respect to its inputs (no branching on time or
    ///   randomness before an input call). A skewed sequence makes a stored
    ///   answer decode into the wrong shape, which rejects the retry with
    ///   `-32602` rather than silently misdelivering data.
    func resolveModernInput<Response: Decodable & Sendable>(
        method: String,
        params: JSONValue?,
        as type: Response.Type
    ) async throws -> Response {
        let ordinalID = await mrtr.nextOrdinalID()
        if let answer = await mrtr.response(for: ordinalID) {
            do {
                return try answer.decoded(type)
            } catch {
                // A present-but-undecodable response is a malformed client
                // input (spec: protocol error), not a tool failure.
                throw MRTRInvalidInputResponse(id: ordinalID, underlying: error)
            }
        }
        throw InputRequiredSignal(id: ordinalID, request: InputRequest(method: method, params: params))
    }

    /// Send a progress notification if a progress token was provided.
    public func reportProgress(_ progress: Double, total: Double? = nil, message: String? = nil) async {
        guard let progressToken = meta?.progressToken else { return }

        await Session.current?.sendProgressNotification(progressToken: progressToken,
                                                        progress: progress,
                                                        total: total,
                                                        message: message)
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
        // Modern (2026-07-28): live server→client requests are illegal — resolve
        // from the MRTR retry's input responses, or signal `input_required`.
        // Capabilities come from the request's `_meta` (there is no session).
        if await protocolProfile.has(.mrtr) {
            guard await effectiveClientCapabilities?.sampling != nil else {
                throw MCPServerError.clientHasNoSamplingSupport
            }
            let params = try JSONDictionary(encoding: request)
            return try await resolveModernInput(
                method: "sampling/createMessage", params: .object(params),
                as: SamplingCreateMessageResponse.self
            )
        }

        guard let session = Session.current else {
            throw MCPServerError.noActiveSession
        }

        // Check if client supports sampling
        guard await session.clientCapabilities?.sampling != nil else {
            throw MCPServerError.clientHasNoSamplingSupport
        }

        // Encode the request parameters
        let params = try JSONDictionary(encoding: request)

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

        return try result.decoded(SamplingCreateMessageResponse.self)
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
        // Modern (2026-07-28): resolve from the MRTR retry's input responses, or
        // signal `input_required`. Capability comes from the request's `_meta`.
        if await protocolProfile.has(.mrtr) {
            guard await effectiveClientCapabilities?.elicitation != nil else {
                throw MCPServerError.clientHasNoElicitationSupport
            }
            let params = try JSONDictionary(encoding: request)
            return try await resolveModernInput(
                method: "elicitation/create", params: .object(params),
                as: ElicitationCreateResponse.self
            )
        }

        guard let session = Session.current else {
            throw MCPServerError.noActiveSession
        }

        // Elicitation was introduced in 2025-06-18. If the session negotiated an
        // earlier revision, the feature is not part of the agreed protocol —
        // refuse rather than emitting an `elicitation/create` the client cannot
        // understand. Gate on the negotiated profile, not just the advertised
        // capability, so a client that over-declares the capability on an older
        // revision is still held to what it negotiated.
        if let version = await session.negotiatedProtocolVersion,
           let profile = MCPProtocolVersion.profile(for: version),
           !profile.has(.elicitation) {
            throw MCPServerError.featureUnavailableInNegotiatedVersion(
                feature: .elicitation,
                version: version
            )
        }

        // Check if client supports elicitation
        let capabilities = await session.clientCapabilities
        guard capabilities?.elicitation != nil else {
            throw MCPServerError.clientHasNoElicitationSupport
        }

        // Encode the request parameters
        let params = try JSONDictionary(encoding: request)

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

        return try result.decoded(ElicitationCreateResponse.self)
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

    /// Notify the client that the list of available tools changed.
    public func sendToolListChanged() async throws {
        try await Session.current?.sendToolListChanged()
    }

    /// Notify the client that the list of available resources changed.
    public func sendResourceListChanged() async throws {
        try await Session.current?.sendResourceListChanged()
    }

    /// Notify the client that the list of available prompts changed.
    public func sendPromptListChanged() async throws {
        try await Session.current?.sendPromptListChanged()
    }
}
