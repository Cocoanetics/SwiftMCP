import Testing
import SwiftMCP

// Regression test: `@MCPExtension` must work when the host type is an
// `actor`. The per-type design emits actor-isolated storage and
// `__mcpRegisterExtension` on actor hosts (so the executor serializes
// register and register-while-dispatch), and the macro-emitted
// `register(in:)` is `async` so a single call shape works for both
// class and actor hosts.

@MCPServer
actor ActorBackedServer {
    /// Return a friendly greeting.
    @MCPTool
    func greet(name: String) -> String {
        "Hello, \(name)!"
    }
}

@MCPExtension("ActorMath")
extension ActorBackedServer {
    /// Add two integers.
    @MCPTool
    // swiftlint:disable:next identifier_name
    func add(a: Int, b: Int) -> Int {
        a + b
    }
}

@Test("Actor host accepts @MCPExtension registration")
func testActorExtensionRegistration() async throws {
    let server = ActorBackedServer()

    // Sanity: primary tool is visible before registering anything.
    await #expect(server.mcpToolMetadata.contains { $0.name == "greet" })
    await #expect(!server.mcpToolMetadata.contains { $0.name == "add" })

    // The bug fix: this call must compile on an actor host. `register(in:)`
    // is `async`; `await` here hops onto the actor's executor.
    await ActorBackedServer.ActorMath.register(in: server)

    await #expect(server.mcpToolMetadata.contains { $0.name == "add" })

    let sum = try await server.callTool("add", arguments: ["a": 7, "b": 5])
    #expect(sum as? Int == 12)

    // Idempotence: registering twice is a no-op (executor serializes
    // both calls; the second hits the `__mcpRegisteredExtensionIDs`
    // guard and returns without re-appending).
    await ActorBackedServer.ActorMath.register(in: server)
    let addCount = await server.mcpToolMetadata.filter { $0.name == "add" }.count
    #expect(addCount == 1)
}

@Test("Concurrent register(in:) calls remain idempotent")
func testConcurrentExtensionRegistration() async throws {
    // Hammer `register(in:)` from many tasks at once. The actor's
    // executor serializes the mutations naturally — no lock, just the
    // language semantics — so the documented "registering twice is a
    // no-op" guarantee holds.
    let server = ActorBackedServer()

    await withTaskGroup(of: Void.self) { group in
        for _ in 0..<256 {
            group.addTask {
                await ActorBackedServer.ActorMath.register(in: server)
            }
        }
    }

    let addCount = await server.mcpToolMetadata.filter { $0.name == "add" }.count
    #expect(addCount == 1)

    let sum = try await server.callTool("add", arguments: ["a": 4, "b": 6])
    #expect(sum as? Int == 10)
}
