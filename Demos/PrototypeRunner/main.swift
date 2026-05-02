//
//  PrototypeRunner — exercises the per-instance extension prototype.
//
//  Demonstrates:
//   - Direct extension registration: `MyServer.<Name>.register(in: server)`
//     is what the aggregator's umbrella calls under the hood, and what users
//     can write themselves with no plugin at all.
//   - Optional umbrella registration: `SwiftMCPBootstrap_<Target>.register(in:)`
//     emitted by the build plugin, which collapses N register calls per
//     target to one.
//

import Foundation
import SwiftMCP
import PrototypeServerLib
import PrototypeExtensionsLib

@main
struct PrototypeRunner {
    static func main() async throws {
        let server = PrototypeServer()

        // Same-target extensions registered explicitly — this works without
        // the build plugin.
        PrototypeServer.Math.register(in: server)
        PrototypeServer.Strings.register(in: server)

        // Cross-target registration via the umbrella emitted by the plugin.
        // Equivalent to writing `PrototypeServer.Calendar.register(in: server)`
        // by hand for every contribution from PrototypeExtensionsLib.
        SwiftMCPBootstrap_PrototypeExtensionsLib.register(in: server)

        print("=== Tools registered on \(server.serverName) ===")
        for tool in server.mcpToolMetadata.sorted(by: { $0.name < $1.name }) {
            let params = tool.parameters.map { "\($0.name): \($0.type)" }.joined(separator: ", ")
            print("  • \(tool.name)(\(params)) — \(tool.description ?? "(no description)")")
        }

        print("\n=== Dispatching ===")
        try await invoke(server, "greet",     args: ["name": .string("World")])
        try await invoke(server, "add",       args: ["a": .integer(7),  "b": .integer(5)])
        try await invoke(server, "multiply",  args: ["a": .integer(6),  "b": .integer(7)])
        try await invoke(server, "shout",     args: ["text": .string("hello")])
        try await invoke(server, "subtract",  args: ["a": .integer(10), "b": .integer(4)])
        try await invoke(server, "echo",      args: ["text": .string("ping")])
    }

    static func invoke(_ server: PrototypeServer, _ name: String, args: JSONDictionary) async throws {
        let result = try await server.callTool(name, arguments: args)
        print("  \(name) → \(result)")
    }
}
