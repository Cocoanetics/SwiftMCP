#if Server
import Testing
import Foundation
import HTTPTypes
@testable import SwiftMCP

@Suite("Official Tasks extension (io.modelcontextprotocol/tasks)", .serialized)
struct TasksExtensionTests {

    init() async {
        await MCPTaskRegistry.shared.removeAll()
        await MCPTaskRegistry.shared.setDefaultTTLMs(MCPTasksExtension.defaultTTLMs)
    }

    // MARK: - Wire shape

    @Test("Pinned extension identifier and empty capability round-trip")
    func schemaPinAndCapabilityShape() throws {
        #expect(MCPTasksExtension.identifier == "io.modelcontextprotocol/tasks")
        #expect(MCPTasksExtension.schemaVersion == "2026-07-28")
        #expect(MCPTasksExtension.schemaSource.contains("ext-tasks"))
        #expect(MCPTasksExtension.capability == .object([:]))

        var caps = ServerCapabilities()
        caps.extensions = [MCPTasksExtension.identifier: MCPTasksExtension.capability]
        let encoded = try JSONEncoder().encode(caps)
        let decoded = try JSONDecoder().decode(ServerCapabilities.self, from: encoded)
        #expect(decoded.extensions?[MCPTasksExtension.identifier] == .object([:]))
    }

    @Test("CreateTaskResult and GetTaskResult wire discriminators")
    func resultDiscriminators() {
        let snapshot = MCPTaskSnapshot(
            taskId: "t-1",
            status: .working,
            statusMessage: nil,
            createdAt: Date(timeIntervalSince1970: 0),
            lastUpdatedAt: Date(timeIntervalSince1970: 0),
            ttlMs: 1000,
            pollIntervalMs: 100,
            inputRequests: nil,
            result: nil,
            error: nil
        )
        let create = snapshot.createTaskResultDictionary()
        #expect(create["resultType"]?.stringValue == "task")
        #expect(create["taskId"]?.stringValue == "t-1")
        #expect(create["status"]?.stringValue == "working")

        let get = snapshot.getTaskResultDictionary()
        #expect(get["resultType"]?.stringValue == "complete")
        #expect(get["taskId"]?.stringValue == "t-1")
    }

    // MARK: - Negotiation

    @Test("Server advertises tasks extension only when a tool opts in")
    func negotiationAdvertisesWhenOptedIn() async throws {
        let withTasks = TasksTestServer()
        let caps = await withTasks.buildServerCapabilities()
        #expect(caps.extensions?[MCPTasksExtension.identifier] == MCPTasksExtension.capability)

        let without = Calculator()
        let bare = await without.buildServerCapabilities()
        #expect(bare.extensions?[MCPTasksExtension.identifier] == nil)
    }

    @Test("Legacy tools/call without the extension stays synchronous")
    func legacyNonTaskCallStillWorks() async throws {
        let transport = HTTPSSETransport(server: TasksTestServer())
        let adapter = InMemoryHTTPServerAdapter(engine: transport)

        let result = try await tasksSend(
            adapter,
            headers: tasksHeaders(method: "tools/call", name: "echo"),
            body: try tasksCallBody(
                tool: "echo",
                arguments: ["text": .string("hi")],
                meta: tasksNoExtensionMeta
            )
        )
        #expect(result["resultType"]?.stringValue != "task")
        let text = result["content"]?.arrayValue?.first?.dictionaryValue?["text"]?.stringValue
        #expect(text == "hi")
    }

    @Test("Required taskSupport without client extension yields -32021")
    func requiredWithoutCapability() async throws {
        let transport = HTTPSSETransport(server: TasksTestServer())
        let adapter = InMemoryHTTPServerAdapter(engine: transport)

        let result = try await tasksSend(
            adapter,
            headers: tasksHeaders(method: "tools/call", name: "mustBeTask"),
            body: try tasksCallBody(tool: "mustBeTask", meta: tasksNoExtensionMeta)
        )
        #expect(result["__error_code"]?.intValue == MCPTasksExtension.missingRequiredClientCapabilityCode)
    }

    // MARK: - Lifecycle / unsolicited handle

    @Test("Opt-in tool returns an unsolicited task handle; polling reaches completed")
    func unsolicitedHandleAndPoll() async throws {
        let transport = HTTPSSETransport(server: TasksTestServer())
        let adapter = InMemoryHTTPServerAdapter(engine: transport)

        let created = try await tasksSend(
            adapter,
            headers: tasksHeaders(method: "tools/call", name: "slowHello"),
            body: try tasksCallBody(tool: "slowHello")
        )
        #expect(created["resultType"]?.stringValue == "task")
        let taskId = try #require(created["taskId"]?.stringValue)
        #expect(created["status"]?.stringValue == "working")

        let final = try await tasksPollUntil(adapter, taskId: taskId)
        #expect(final["resultType"]?.stringValue == "complete")
        #expect(final["status"]?.stringValue == "completed")
        let toolResult = try #require(final["result"]?.dictionaryValue)
        let text = toolResult["content"]?.arrayValue?.first?.dictionaryValue?["text"]?.stringValue
        #expect(text == "hello-task")
    }

    @Test("tasks/list and tasks/result remain unknown methods")
    func supersededMethodsStayGone() async {
        let server = TasksTestServer()
        for method in ["tasks/list", "tasks/result"] {
            let response = await server.handleMessage(
                .request(id: 1, method: method, params: .object(["taskId": .string("x")]))
            )
            guard case .errorResponse(let err) = response else {
                Issue.record("\(method) should be -32601")
                continue
            }
            #expect(err.error.code == -32601)
        }
    }

    // MARK: - Input update

    @Test("input_required then tasks/update completes the task")
    func inputUpdateRoundTrip() async throws {
        let transport = HTTPSSETransport(server: TasksTestServer())
        let adapter = InMemoryHTTPServerAdapter(engine: transport)

        let created = try await tasksSend(
            adapter,
            headers: tasksHeaders(method: "tools/call", name: "askNameTask"),
            body: try tasksCallBody(tool: "askNameTask")
        )
        let taskId = try #require(created["taskId"]?.stringValue)

        let waiting = try await tasksPollUntil(adapter, taskId: taskId)
        #expect(waiting["status"]?.stringValue == "input_required")
        let requests = try #require(waiting["inputRequests"]?.dictionaryValue)
        let key = try #require(requests.keys.first)

        let ack = try await tasksSend(
            adapter,
            headers: tasksHeaders(method: "tasks/update", name: taskId),
            body: try tasksMethodBody(
                method: "tasks/update",
                params: [
                    "taskId": .string(taskId),
                    "inputResponses": .object([
                        key: .object([
                            "action": .string("accept"),
                            "content": .object(["name": .string("Luca")])
                        ])
                    ])
                ]
            )
        )
        #expect(ack["resultType"]?.stringValue == "complete")
        #expect(ack["__error_code"] == nil)

        let final = try await tasksPollUntil(adapter, taskId: taskId)
        #expect(final["status"]?.stringValue == "completed")
        let toolResult = try #require(final["result"]?.dictionaryValue)
        let text = toolResult["content"]?.arrayValue?.first?.dictionaryValue?["text"]?.stringValue
        #expect(text == "Hello Luca")
    }

    // MARK: - Cross-principal isolation

    @Test("A different access token cannot observe another principal's task")
    func crossPrincipalIsolation() async throws {
        let transport = HTTPSSETransport(server: TasksTestServer())
        let adapter = InMemoryHTTPServerAdapter(engine: transport)

        let ownerMeta = tasksMeta(accessToken: "owner-token")
        let created = try await tasksSend(
            adapter,
            headers: tasksHeaders(method: "tools/call", name: "slowHello"),
            body: try tasksCallBody(tool: "slowHello", meta: ownerMeta)
        )
        let taskId = try #require(created["taskId"]?.stringValue)

        let otherMeta = tasksMeta(accessToken: "intruder-token")
        let denied = try await tasksSend(
            adapter,
            headers: tasksHeaders(method: "tasks/get", name: taskId),
            body: try tasksMethodBody(
                method: "tasks/get",
                params: ["taskId": .string(taskId)],
                meta: otherMeta
            )
        )
        #expect(denied["__error_code"]?.intValue == -32602)

        let allowed = try await tasksSend(
            adapter,
            headers: tasksHeaders(method: "tasks/get", name: taskId),
            body: try tasksMethodBody(
                method: "tasks/get",
                params: ["taskId": .string(taskId)],
                meta: ownerMeta
            )
        )
        #expect(allowed["__error_code"] == nil)
        #expect(allowed["taskId"]?.stringValue == taskId)
    }

    // MARK: - Cancellation / retention

    @Test("tasks/cancel acknowledges and the task becomes cancelled")
    func cancellation() async throws {
        let transport = HTTPSSETransport(server: TasksTestServer())
        let adapter = InMemoryHTTPServerAdapter(engine: transport)

        // Use the eliciting tool so we have time to cancel before completion.
        let created = try await tasksSend(
            adapter,
            headers: tasksHeaders(method: "tools/call", name: "askNameTask"),
            body: try tasksCallBody(tool: "askNameTask")
        )
        let taskId = try #require(created["taskId"]?.stringValue)
        _ = try await tasksPollUntil(adapter, taskId: taskId) // wait until input_required

        let ack = try await tasksSend(
            adapter,
            headers: tasksHeaders(method: "tasks/cancel", name: taskId),
            body: try tasksMethodBody(
                method: "tasks/cancel",
                params: ["taskId": .string(taskId)]
            )
        )
        #expect(ack["resultType"]?.stringValue == "complete")

        let state = try await tasksSend(
            adapter,
            headers: tasksHeaders(method: "tasks/get", name: taskId),
            body: try tasksMethodBody(
                method: "tasks/get",
                params: ["taskId": .string(taskId)]
            )
        )
        #expect(state["status"]?.stringValue == "cancelled")
    }

    @Test("Expired tasks are purged and report not found")
    func boundedRetention() async throws {
        await MCPTaskRegistry.shared.setDefaultTTLMs(1)

        let transport = HTTPSSETransport(server: TasksTestServer())
        let adapter = InMemoryHTTPServerAdapter(engine: transport)

        let created = try await tasksSend(
            adapter,
            headers: tasksHeaders(method: "tools/call", name: "slowHello"),
            body: try tasksCallBody(tool: "slowHello")
        )
        let taskId = try #require(created["taskId"]?.stringValue)

        try await Task.sleep(for: .milliseconds(20))

        let expired = try await tasksSend(
            adapter,
            headers: tasksHeaders(method: "tasks/get", name: taskId),
            body: try tasksMethodBody(
                method: "tasks/get",
                params: ["taskId": .string(taskId)]
            )
        )
        #expect(expired["__error_code"]?.intValue == -32602)
    }

}
#endif
