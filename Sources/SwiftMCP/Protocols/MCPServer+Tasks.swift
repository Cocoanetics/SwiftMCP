//
//  MCPServer+Tasks.swift
//  SwiftMCP
//
//  Official `io.modelcontextprotocol/tasks` methods: `tasks/get`,
//  `tasks/update`, `tasks/cancel`, plus helpers for unsolicited task handles
//  from `tools/call`.
//

import Foundation

/// Bundles the inputs needed to start and run a task-augmented tool call.
struct TaskAugmentedCall: Sendable {
    let toolName: String
    let arguments: JSONDictionary
    let metadata: MCPToolMetadata?
    let includeStructuredContent: Bool
    let includeResourceLinks: Bool

    var expectsToolResult: Bool { metadata?.returnTypeIsContent ?? false }
}

public extension MCPServer {

    // MARK: - Capability helpers

    /// Whether the current client declared the Tasks extension.
    internal func clientSupportsTasksExtension() async -> Bool {
        let capabilities = await RequestContext.current?.effectiveClientCapabilities
        guard let extensions = capabilities?.extensions else { return false }
        return extensions[MCPTasksExtension.identifier] != nil
    }

    /// Whether any tool on this server opts into task-augmented execution.
    internal func serverAdvertisesTasksExtension() async -> Bool {
        guard let toolProvider = self as? MCPToolProviding else { return false }
        let metadata = await toolProvider.mcpToolMetadata
        return metadata.contains { $0.taskSupport != .forbidden }
    }

    /// `-32021` Missing Required Client Capability for the Tasks extension.
    internal func missingTasksCapabilityError(id: JSONRPCID) -> JSONRPCMessage {
        JSONRPCMessage.errorResponse(
            id: id,
            error: .init(
                code: MCPTasksExtension.missingRequiredClientCapabilityCode,
                message: "Missing required client capability",
                data: .object([
                    "requiredCapabilities": .object([
                        "extensions": .object([
                            MCPTasksExtension.identifier: MCPTasksExtension.capability
                        ])
                    ])
                ])
            )
        )
    }

    // MARK: - Method handlers

    internal func handleTasksGet(
        _ request: JSONRPCMessage.JSONRPCRequestData
    ) async -> JSONRPCMessage {
        if !(await clientSupportsTasksExtension()) {
            return missingTasksCapabilityError(id: request.id)
        }
        guard let taskId = request.params?["taskId"]?.stringValue else {
            return JSONRPCMessage.errorResponse(
                id: request.id,
                error: .init(code: -32602, message: "Invalid params: missing taskId")
            )
        }
        let owner = await MCPTaskPrincipal.current()
        guard let record = await MCPTaskRegistry.shared.task(id: taskId, for: owner) else {
            return JSONRPCMessage.errorResponse(
                id: request.id,
                error: .init(code: -32602, message: "Failed to retrieve task: Task not found")
            )
        }
        let snapshot = await record.snapshot()
        return JSONRPCMessage.response(id: request.id, result: .object(snapshot.getTaskResultDictionary()))
    }

    internal func handleTasksUpdate(
        _ request: JSONRPCMessage.JSONRPCRequestData
    ) async -> JSONRPCMessage {
        if !(await clientSupportsTasksExtension()) {
            return missingTasksCapabilityError(id: request.id)
        }
        guard let taskId = request.params?["taskId"]?.stringValue else {
            return JSONRPCMessage.errorResponse(
                id: request.id,
                error: .init(code: -32602, message: "Invalid params: missing taskId")
            )
        }
        let responses = request.params?["inputResponses"]?.dictionaryValue ?? [:]
        let owner = await MCPTaskPrincipal.current()
        guard let record = await MCPTaskRegistry.shared.task(id: taskId, for: owner) else {
            return JSONRPCMessage.errorResponse(
                id: request.id,
                error: .init(code: -32602, message: "Failed to retrieve task: Task not found")
            )
        }
        await record.applyInputResponses(responses)
        return JSONRPCMessage.response(
            id: request.id,
            result: .object(["resultType": .string("complete")])
        )
    }

    internal func handleTasksCancel(
        _ request: JSONRPCMessage.JSONRPCRequestData
    ) async -> JSONRPCMessage {
        if !(await clientSupportsTasksExtension()) {
            return missingTasksCapabilityError(id: request.id)
        }
        guard let taskId = request.params?["taskId"]?.stringValue else {
            return JSONRPCMessage.errorResponse(
                id: request.id,
                error: .init(code: -32602, message: "Invalid params: missing taskId")
            )
        }
        let owner = await MCPTaskPrincipal.current()
        guard let record = await MCPTaskRegistry.shared.task(id: taskId, for: owner) else {
            return JSONRPCMessage.errorResponse(
                id: request.id,
                error: .init(code: -32602, message: "Failed to retrieve task: Task not found")
            )
        }
        await record.requestCancellation()
        return JSONRPCMessage.response(
            id: request.id,
            result: .object(["resultType": .string("complete")])
        )
    }

    // MARK: - Unsolicited task-augmented tools/call

    /// Creates a durable task handle and runs the tool asynchronously.
    internal func startTaskAugmentedToolCall(
        request: JSONRPCMessage.JSONRPCRequestData,
        call: TaskAugmentedCall
    ) async -> JSONRPCMessage {
        let owner = await MCPTaskPrincipal.current()
        let record = await MCPTaskRegistry.shared.create(owner: owner)
        let box = UncheckedServerBox(server: self)

        await record.startWork {
            await MCPTaskRecord.$current.withValue(record) {
                await box.server.executeTaskAugmentedTool(record: record, call: call)
            }
        }

        let snapshot = await record.snapshot()
        return JSONRPCMessage.response(
            id: request.id,
            result: .object(snapshot.createTaskResultDictionary())
        )
    }

    /// Runs the tool body for a task and records the terminal state.
    internal func executeTaskAugmentedTool(
        record: MCPTaskRecord,
        call: TaskAugmentedCall
    ) async {
        guard let toolProvider = self as? MCPToolProviding else {
            await record.fail(
                with: .init(code: -32601, message: "Method not found"),
                statusMessage: "Server does not provide tools"
            )
            return
        }

        do {
            let result = try await toolProvider.callTool(call.toolName, arguments: call.arguments)
            let wrappedResult = try call.metadata?.wrapOutputIfNeeded(result) ?? result
            let payload = try encodeToolCallResultPayload(
                wrappedResult: wrappedResult,
                expectsToolResult: call.expectsToolResult,
                includeStructuredContent: call.includeStructuredContent,
                includeResourceLinks: call.includeResourceLinks,
                isError: false
            )
            await record.complete(with: payload)
        } catch is CancellationError {
            if await record.wasCancellationRequested() {
                // `requestCancellation` already transitioned to cancelled.
                return
            }
            await record.fail(
                with: .init(code: -32603, message: "Cancelled"),
                statusMessage: "Task work was cancelled"
            )
        } catch let invalid as MRTRInvalidInputResponse {
            await record.fail(
                with: .init(
                    code: -32602,
                    message: "Invalid input response for \(invalid.id): \(invalid.underlying)"
                )
            )
        } catch {
            // Tool-level failures complete with isError: true (not task `failed`).
            let payload: JSONDictionary = [
                "content": .array([.object([
                    "type": .string("text"),
                    "text": .string(error.localizedDescription)
                ])]),
                "isError": true
            ]
            await record.complete(with: payload, statusMessage: error.localizedDescription)
        }
    }
}
