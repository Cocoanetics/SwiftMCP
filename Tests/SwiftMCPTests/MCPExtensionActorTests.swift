import Testing
import SwiftMCP

// Regression test: `@MCPExtension` must work when the host type is an
// `actor`. The generated `register(in:)` is a synchronous static func that
// calls `__mcpRegisterExtension` on the server instance — so that method
// must be `nonisolated` on actor hosts, otherwise the registration site
// fails to compile with "call to actor-isolated instance method ... in a
// synchronous nonisolated context".

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
    #expect(server.mcpToolMetadata.contains { $0.name == "greet" })
    #expect(!server.mcpToolMetadata.contains { $0.name == "add" })

    // The bug fix: this call must compile on an actor host.
    ActorBackedServer.ActorMath.register(in: server)

    #expect(server.mcpToolMetadata.contains { $0.name == "add" })

    let sum = try await server.callTool("add", arguments: ["a": 7, "b": 5])
    #expect(sum as? Int == 12)

    // Idempotence: registering twice is a no-op.
    ActorBackedServer.ActorMath.register(in: server)
    let addCount = server.mcpToolMetadata.filter { $0.name == "add" }.count
    #expect(addCount == 1)
}

@Test("Concurrent register(in:) calls remain idempotent")
func testConcurrentExtensionRegistration() async throws {
    // Hammer `register(in:)` from many tasks at once. With `nonisolated`
    // registration on an actor host, the storage no longer gets actor-
    // executor serialization — `__mcpExtensionLock` must keep the
    // Set/Array mutations safe and preserve the documented "registering
    // twice is a no-op" guarantee.
    let server = ActorBackedServer()

    await withTaskGroup(of: Void.self) { group in
        for _ in 0..<256 {
            group.addTask {
                ActorBackedServer.ActorMath.register(in: server)
            }
        }
    }

    let addCount = server.mcpToolMetadata.filter { $0.name == "add" }.count
    #expect(addCount == 1)

    let sum = try await server.callTool("add", arguments: ["a": 4, "b": 6])
    #expect(sum as? Int == 10)
}
