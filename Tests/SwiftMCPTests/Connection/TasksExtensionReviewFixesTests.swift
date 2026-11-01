#if Server
import Testing
import Foundation
@testable import SwiftMCP

/// Review-fix regressions for #229; lives on the same serialized suite as
/// ``TasksExtensionTests`` so both share one `MCPTaskRegistry` timeline.
extension TasksExtensionTests {

    @Test("tasks/update without inputResponses is rejected with -32602")
    func updateRequiresInputResponses() async throws {
        let transport = HTTPSSETransport(server: TasksTestServer())
        let adapter = InMemoryHTTPServerAdapter(engine: transport)

        let created = try await tasksSend(
            adapter,
            headers: tasksHeaders(method: "tools/call", name: "askNameTask"),
            body: try tasksCallBody(tool: "askNameTask")
        )
        let taskId = try #require(created["taskId"]?.stringValue)
        _ = try await tasksPollUntil(adapter, taskId: taskId)

        let rejected = try await tasksSend(
            adapter,
            headers: tasksHeaders(method: "tasks/update", name: taskId),
            body: try tasksMethodBody(
                method: "tasks/update",
                params: ["taskId": .string(taskId)]
            )
        )
        #expect(rejected["__error_code"]?.intValue == -32602)

        // Still waiting for real input — not falsely acknowledged.
        let waiting = try await tasksSend(
            adapter,
            headers: tasksHeaders(method: "tasks/get", name: taskId),
            body: try tasksMethodBody(
                method: "tasks/get",
                params: ["taskId": .string(taskId)]
            )
        )
        #expect(waiting["status"]?.stringValue == "input_required")
    }

    @Test("awaitInput after cancel throws instead of resurrecting input_required")
    func awaitInputRespectsPriorCancellation() async throws {
        let record = MCPTaskRecord(
            taskId: "cancel-race",
            owner: MCPTaskPrincipal(rawValue: "test"),
            ttlMs: 60_000,
            pollIntervalMs: 100
        )
        await record.requestCancellation()
        await #expect(throws: CancellationError.self) {
            _ = try await record.awaitInput(method: "elicitation/create", params: .object([:]))
        }
        let snapshot = await record.snapshot()
        #expect(snapshot.status == .cancelled)
    }

    @Test("Creating a task sweeps other expired records from the registry")
    func createSweepsExpiredTasks() async throws {
        await MCPTaskRegistry.shared.setDefaultTTLMs(1)
        let owner = MCPTaskPrincipal(rawValue: "sweep-owner")
        let stale = await MCPTaskRegistry.shared.create(owner: owner, ttlMs: 1)
        let staleId = await stale.taskId
        try await Task.sleep(for: .milliseconds(20))

        _ = await MCPTaskRegistry.shared.create(owner: owner, ttlMs: 60_000)
        let purged = await MCPTaskRegistry.shared.task(id: staleId, for: owner)
        #expect(purged == nil)

        await MCPTaskRegistry.shared.setDefaultTTLMs(MCPTasksExtension.defaultTTLMs)
    }
}
#endif
