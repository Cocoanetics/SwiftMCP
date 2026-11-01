#if Server
import Testing
import Foundation
import HTTPTypes
@testable import SwiftMCP

/// Fixture server for the official Tasks extension.
@MCPServer(name: "TasksTestServer", version: "1.0")
actor TasksTestServer {
    /// Fast synchronous tool — never task-augmented (default forbidden).
    @MCPTool(description: "Echoes a value", hints: [.readOnly])
    func echo(text: String) -> String {
        text
    }

    /// Opt-in optional task tool that finishes without client input.
    @MCPTool(description: "Slow hello via task", taskSupport: .optional)
    func slowHello() async -> String {
        "hello-task"
    }

    /// Opt-in task tool that elicits mid-flight.
    @MCPTool(description: "Greets after eliciting via task", taskSupport: .optional)
    func askNameTask() async throws -> String {
        let response = try await RequestContext.current.elicit(
            message: "Your name?",
            schema: .object(JSONSchema.Object(properties: ["name": .string()], required: ["name"]))
        )
        let name = response.content?["name"]?.stringValue ?? "nobody"
        return "Hello \(name)"
    }

    /// Requires the Tasks extension — clients without it get -32021.
    @MCPTool(description: "Requires tasks", taskSupport: .required)
    func mustBeTask() -> String {
        "required-ok"
    }
}

let tasksExtensionMeta: JSONValue = .object([
    "io.modelcontextprotocol/protocolVersion": .string("2026-07-28"),
    "io.modelcontextprotocol/clientCapabilities": .object([
        "elicitation": .object([:]),
        "extensions": .object([
            MCPTasksExtension.identifier: MCPTasksExtension.capability
        ])
    ])
])

let tasksNoExtensionMeta: JSONValue = .object([
    "io.modelcontextprotocol/protocolVersion": .string("2026-07-28"),
    "io.modelcontextprotocol/clientCapabilities": .object([
        "elicitation": .object([:])
    ])
])

func tasksMeta(accessToken: String?) -> JSONValue {
    var meta: JSONDictionary = [
        "io.modelcontextprotocol/protocolVersion": .string("2026-07-28"),
        "io.modelcontextprotocol/clientCapabilities": .object([
            "elicitation": .object([:]),
            "extensions": .object([
                MCPTasksExtension.identifier: MCPTasksExtension.capability
            ])
        ])
    ]
    if let accessToken {
        meta["accessToken"] = .string(accessToken)
    }
    return .object(meta)
}

func tasksCallBody(
    tool: String,
    arguments: JSONDictionary = [:],
    meta: JSONValue = tasksExtensionMeta,
    id: Int = 1
) throws -> Data {
    let params: JSONDictionary = [
        "name": .string(tool),
        "arguments": .object(arguments),
        "_meta": meta
    ]
    return try HTTPTransportTestHelpers.encode(
        JSONRPCMessage.request(id: id, method: "tools/call", params: .object(params))
    )
}

func tasksMethodBody(
    method: String,
    params: JSONDictionary,
    meta: JSONValue = tasksExtensionMeta,
    id: Int = 1
) throws -> Data {
    var full = params
    full["_meta"] = meta
    return try HTTPTransportTestHelpers.encode(
        JSONRPCMessage.request(id: id, method: method, params: .object(full))
    )
}

func tasksHeaders(method: String, name: String) -> HTTPFields {
    [
        .accept: "application/json, text/event-stream",
        .contentType: "application/json",
        .mcpProtocolVersion: "2026-07-28",
        .mcpMethod: method,
        .mcpName: name
    ]
}

func tasksSend(
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
        var dict: JSONDictionary = [
            "__error_code": .integer(data.error.code),
            "__error_message": .string(data.error.message)
        ]
        if let errorData = data.error.data {
            dict["__error_data"] = errorData
        }
        return dict
    default:
        Issue.record("unexpected message shape: \(message)")
        return [:]
    }
}

func tasksPollUntil(
    _ adapter: InMemoryHTTPServerAdapter,
    taskId: String,
    meta: JSONValue = tasksExtensionMeta,
    timeoutMs: Int = 5_000
) async throws -> JSONDictionary {
    let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1_000)
    var last: JSONDictionary = [:]
    while Date() < deadline {
        last = try await tasksSend(
            adapter,
            headers: tasksHeaders(method: "tasks/get", name: taskId),
            body: try tasksMethodBody(
                method: "tasks/get",
                params: ["taskId": .string(taskId)],
                meta: meta
            )
        )
        if last["__error_code"] != nil {
            return last
        }
        let status = last["status"]?.stringValue
        if status == "completed" || status == "failed" || status == "cancelled"
            || status == "input_required" {
            return last
        }
        try await Task.sleep(for: .milliseconds(20))
    }
    return last
}
#endif
