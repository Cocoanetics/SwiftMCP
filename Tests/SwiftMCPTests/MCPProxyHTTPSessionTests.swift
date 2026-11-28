#if Client
import Testing
import SwiftCross
@testable import SwiftMCP

/// `retire()` must end work even when the Foundation call behind it ignores
/// cancellation, as SwiftCross's `bytes(for:)` shim does until headers arrive
/// off Apple platforms. (#277)
@Suite("MCPProxyHTTPSession retirement", .timeLimit(.minutes(1)))
struct MCPProxyHTTPSessionTests {
    @Test("Retiring fails a start whose Foundation call ignores cancellation")
    func retireFailsUncancellableStart() async throws {
        let session = MCPProxyHTTPSession(configuration: .default)
        let call = StartGate()
        let request = Task {
            try await session.start { _ in
                // Stands in for a call that neither returns nor observes cancellation.
                await call.pass()
                return 1
            }
        }
        await call.waitForArrival()

        session.retire()
        await #expect(throws: CancellationError.self) {
            _ = try await request.value
        }
        await call.release()
    }

    @Test("Retiring cancels an operation still reading its response")
    func retireCancelsRunningOperation() async throws {
        let session = MCPProxyHTTPSession(configuration: .default)
        let running = StartGate()
        let operation = Task {
            try await session.run {
                await running.pass()
                // Reading a body until cancelled.
                while true {
                    try await Task.sleep(nanoseconds: 10_000_000)
                }
            }
        }
        await running.waitForArrival()
        await running.release()

        session.retire()
        await #expect(throws: CancellationError.self) {
            try await operation.value
        }
    }

    @Test("A retired session refuses new starts and operations")
    func retiredSessionRefusesWork() async throws {
        let session = MCPProxyHTTPSession(configuration: .default)
        session.retire()

        await #expect(throws: CancellationError.self) {
            _ = try await session.start { _ in 1 }
        }
        await #expect(throws: CancellationError.self) {
            _ = try await session.run { 1 }
        }
        #expect(session.startedTasks == 0)
    }
}
#endif
