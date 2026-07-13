import Foundation
import Testing
import SwiftMCP

/// A server whose tool suspends until released — proves the in-process loopback
/// dispatches messages task-per-message like the old pipe bridge, instead of
/// awaiting each handler inline in the read loop. Under serial dispatch,
/// `release` (and even `pendingWaiters`) could never run while `waitForRelease`
/// is suspended, deadlocking every concurrent client call.
@MCPServer(name: "DeferredToolServer", version: "1.0.0")
private actor DeferredToolServer {
    private var waiters: [CheckedContinuation<String, Never>] = []

    /// Number of calls currently suspended in `waitForRelease`.
    @MCPTool
    func pendingWaiters() -> Int {
        waiters.count
    }

    /// Suspends until `release` is called, then returns "released".
    @MCPTool
    func waitForRelease() async -> String {
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    /// Resumes every suspended `waitForRelease` call.
    @MCPTool
    func release() -> String {
        for waiter in waiters {
            waiter.resume(returning: "released")
        }
        waiters.removeAll()
        return "ok"
    }
}

struct InProcessLoopbackConcurrencyTests {
    @Test("STDIO in-process: requests dispatch concurrently, not serially",
          .timeLimit(.minutes(1)))
    func inProcessRequestsDispatchConcurrently() async throws {
        let server = DeferredToolServer()
        let proxy = MCPServerProxy(config: .stdioHandles(server: server))
        try await proxy.connect()

        let deferred = Task {
            try await proxy.callTool("waitForRelease")
        }

        // Poll with concurrent tool calls until the deferred call is suspended
        // server-side. The polls themselves require concurrent dispatch: with a
        // serial read loop they would queue behind `waitForRelease` forever and
        // the time limit would fail the test.
        var waiters = 0
        let deadline = DispatchTime.now().uptimeNanoseconds + 15_000_000_000
        while waiters == 0, DispatchTime.now().uptimeNanoseconds < deadline {
            waiters = try await Int(proxy.callTool("pendingWaiters")) ?? 0
            if waiters == 0 {
                try await Task.sleep(nanoseconds: 50_000_000)
            }
        }
        #expect(waiters == 1)

        _ = try await proxy.callTool("release")
        let result = try await deferred.value
        #expect(result == "released")

        await proxy.disconnect()
    }
}
