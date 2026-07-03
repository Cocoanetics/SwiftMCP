#if Server
import Testing
import Foundation
import HTTPTypes
@testable import SwiftMCP

/// A server whose tools/prompts need client input — the MRTR fixtures.
@MCPServer(name: "MRTRServer", version: "1.0")
actor MRTRTestServer {
    /// Greets the user after asking for their name.
    /// - Returns: The greeting.
    @MCPTool(description: "Greets after eliciting a name")
    func askName() async throws -> String {
        let response = try await RequestContext.current.elicit(
            message: "Your name?",
            schema: .object(JSONSchema.Object(properties: ["name": .string()], required: ["name"]))
        )
        let name = response.content?["name"]?.stringValue ?? "nobody"
        return "Hello \(name)"
    }

    /// A prompt that needs the user's name first.
    /// - Returns: The prompt messages.
    @MCPPrompt(description: "Personalized greeting prompt")
    func greetPrompt() async throws -> [PromptMessage] {
        let response = try await RequestContext.current.elicit(
            message: "Your name?",
            schema: .object(JSONSchema.Object(properties: ["name": .string()], required: ["name"]))
        )
        let name = response.content?["name"]?.stringValue ?? "nobody"
        return [PromptMessage(role: .user, content: .init(text: "Greet \(name)"))]
    }

    /// Scales a number after eliciting a label.
    /// - Parameter value: The number to echo.
    /// - Returns: Label and value.
    @MCPTool(description: "Labels a value after eliciting")
    func labelValue(value: Double) async throws -> String {
        let response = try await RequestContext.current.elicit(
            message: "Label?", schema: .object(JSONSchema.Object(properties: ["label": .string()], required: []))
        )
        let label = response.content?["label"]?.stringValue ?? "?"
        return "\(label):\(value)"
    }

    /// Combines two sequential elicitations.
    /// - Returns: Both answers.
    @MCPTool(description: "Elicits twice")
    func askTwo() async throws -> String {
        let first = try await RequestContext.current.elicit(
            message: "First?", schema: .object(JSONSchema.Object(properties: ["a": .string()], required: []))
        )
        let second = try await RequestContext.current.elicit(
            message: "Second?", schema: .object(JSONSchema.Object(properties: ["b": .string()], required: []))
        )
        let firstAnswer = first.content?["a"]?.stringValue ?? "?"
        let secondAnswer = second.content?["b"]?.stringValue ?? "?"
        return "\(firstAnswer)+\(secondAnswer)"
    }
}

// MARK: - Shared fixtures/helpers for both MRTR suites

let mrtrModernMeta: JSONValue = .object([
    "io.modelcontextprotocol/protocolVersion": .string("2026-07-28"),
    "io.modelcontextprotocol/clientCapabilities": .object(["elicitation": .object([:])])
])

func mrtrCallBody(
    tool: String,
    extraParams: JSONDictionary = [:],
    meta: JSONValue = mrtrModernMeta
) throws -> Data {
    var params: JSONDictionary = [
        "name": .string(tool),
        "arguments": .object([:]),
        "_meta": meta
    ]
    for (key, value) in extraParams { params[key] = value }
    return try HTTPTransportTestHelpers.encode(
        JSONRPCMessage.request(id: 1, method: "tools/call", params: .object(params))
    )
}

func mrtrCallHeaders(tool: String) -> HTTPFields {
    [
        .accept: "application/json, text/event-stream", .contentType: "application/json",
        .mcpProtocolVersion: "2026-07-28", .mcpMethod: "tools/call", .mcpName: tool
    ]
}

/// Sends a modern POST and returns the decoded JSON-RPC result dictionary.
func mrtrSend(
    _ adapter: InMemoryHTTPServerAdapter,
    headers: HTTPFields,
    body: Data
) async throws -> JSONDictionary {
    let exchange = await adapter.send(method: .post, path: "/mcp", headerFields: headers, body: body)
    var payload = Data()
    switch exchange.body {
    case .sse(let stream):
        for await chunk in stream { payload.append(chunk) }
    case .buffered(let data):
        payload = data ?? Data()
    }
    let text = String(bytes: payload, encoding: .utf8) ?? ""
    // Extract the first SSE `data:` line (or take the buffered body verbatim).
    let json: String
    if let dataLine = text.split(separator: "\n").first(where: { $0.hasPrefix("data: ") }) {
        json = String(dataLine.dropFirst("data: ".count))
    } else {
        json = text
    }
    let message = try HTTPTransportTestHelpers.decode(Data(json.utf8))
    switch message {
    case .response(let data):
        return data.result?.dictionaryValue ?? [:]
    case .errorResponse(let data):
        return ["__error_code": .integer(data.error.code), "__error_message": .string(data.error.message)]
    default:
        Issue.record("unexpected message shape: \(message)")
        return [:]
    }
}

func mrtrAcceptResponse(_ fields: JSONDictionary) -> JSONValue {
    .object(["action": .string("accept"), "content": .object(fields)])
}
#endif
