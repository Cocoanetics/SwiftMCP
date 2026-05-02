//
//  PrototypeRunner — exercises the extension-aggregation prototype.
//
//  Calls both per-target bootstrap functions, then lists and dispatches
//  every tool on PrototypeServer to verify primary + same-target +
//  cross-target tools all surface and execute.
//

import Foundation
import SwiftMCP
import PrototypeServerLib
import PrototypeExtensionsLib

@main
struct PrototypeRunner {
    static func main() async throws {
        // Register extension tools from each contributing target.
        // (Per-target bootstrap is the v1 UX; an "umbrella" plugin can
        // collapse this to a single call later.)
        SwiftMCPBootstrap_PrototypeServerLib.register()
        SwiftMCPBootstrap_PrototypeExtensionsLib.register()

        let server = PrototypeServer()

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
