//
//  PrototypeRunner — exercises the per-instance @MCPExtension prototype.
//
//  Each `@MCPExtension`-annotated extension is registered explicitly on a
//  server instance. Calling `register(in:)` more than once is a no-op
//  (idempotent on the extension's metatype identity).
//

import Foundation
import SwiftMCP
import PrototypeServerLib
import PrototypeExtensionsLib

@main
struct PrototypeRunner {
    static func main() async throws {
        let server = PrototypeServer()

        // Same-target extensions.
        PrototypeServer.Math.register(in: server)
        PrototypeServer.Strings.register(in: server)

        // Cross-target extension (defined in PrototypeExtensionsLib).
        #if os(macOS) || os(Linux) || os(Windows) || os(iOS)
        PrototypeServer.Calendar.register(in: server)
        #endif

        // Demonstrate idempotence — these calls are no-ops.
        PrototypeServer.Math.register(in: server)
        PrototypeServer.Strings.register(in: server)

        print("=== Tools ===")
        for tool in server.mcpToolMetadata.sorted(by: { $0.name < $1.name }) {
            let params = tool.parameters.map { "\($0.name): \($0.type)" }.joined(separator: ", ")
            print("  • \(tool.name)(\(params)) — \(tool.description ?? "(no description)")")
        }

        print("\n=== Resources ===")
        for resource in server.mcpResourceMetadata.sorted(by: { $0.functionMetadata.name < $1.functionMetadata.name }) {
            let templates = resource.uriTemplates.sorted().joined(separator: ", ")
            print("  • \(resource.name) [\(templates)] — \(resource.description ?? "(no description)")")
        }

        print("\n=== Prompts ===")
        for prompt in server.mcpPromptMetadata.sorted(by: { $0.name < $1.name }) {
            let params = prompt.parameters.map { "\($0.name): \($0.type)" }.joined(separator: ", ")
            print("  • \(prompt.name)(\(params)) — \(prompt.description ?? "(no description)")")
        }

        print("\n=== Dispatching tools ===")
        try await invokeTool(server, "greet",     args: ["name": .string("World")])
        try await invokeTool(server, "add",       args: ["a": .integer(7),  "b": .integer(5)])
        try await invokeTool(server, "multiply",  args: ["a": .integer(6),  "b": .integer(7)])
        try await invokeTool(server, "shout",     args: ["text": .string("hello")])
        #if os(macOS) || os(Linux) || os(Windows) || os(iOS)
        try await invokeTool(server, "subtract",  args: ["a": .integer(10), "b": .integer(4)])
        #endif

        print("\n=== Dispatching resources ===")
        try await invokeResource(server, URL(string: "strings://greet/Alice")!)
        #if os(macOS) || os(Linux) || os(Windows) || os(iOS)
        try await invokeResource(server, URL(string: "calendar://today")!)
        #endif

        print("\n=== Dispatching prompts ===")
        try await invokePrompt(server, "summarizePrompt", args: ["text": .string("Lorem ipsum dolor sit amet.")])
        #if os(macOS) || os(Linux) || os(Windows) || os(iOS)
        try await invokePrompt(server, "schedulingPrompt", args: ["person": .string("Carol")])
        #endif
    }

    static func invokeTool(_ server: PrototypeServer, _ name: String, args: JSONDictionary) async throws {
        let result = try await server.callTool(name, arguments: args)
        print("  \(name) → \(result)")
    }

    static func invokeResource(_ server: PrototypeServer, _ uri: URL) async throws {
        let contents = try await server.getResource(uri: uri)
        let text = contents.first?.text ?? "(no content)"
        print("  \(uri.absoluteString) → \(text)")
    }

    static func invokePrompt(_ server: PrototypeServer, _ name: String, args: JSONDictionary) async throws {
        let messages = try await server.callPrompt(name, arguments: args)
        let summary = messages.map { $0.content.text ?? "?" }.joined(separator: " | ")
        print("  \(name) → \(summary)")
    }

    /// Compile-only check: every extension-contributed method is reachable
    /// on the typed `PrototypeServer.Client` thanks to the aggregator plugin's
    /// emitted Client extensions. Never invoked at runtime.
    @inline(never) static func _clientSurfaceSmokeTest(_ client: PrototypeServer.Client) throws {
        // Primary
        _ = try client.greet(name: "")
        // Same-target Math/Strings extensions
        _ = try client.add(a: 0, b: 0)
        _ = try client.multiply(a: 0, b: 0)
        _ = try client.shout("")
        _ = try client.greetingResource(name: "")
        _ = try client.summarizePrompt(text: "")
        // Cross-target Calendar extension
        #if os(macOS) || os(Linux) || os(Windows) || os(iOS)
        _ = try client.subtract(a: 0, b: 0)
        _ = try client.todayResource()
        _ = try client.schedulingPrompt(person: "")
        #endif
    }
}
