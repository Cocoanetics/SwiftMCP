//
//  PrototypeRunner — exercises the per-instance extension prototype with
//  full tool, resource, and prompt support across same-target and cross-
//  target extensions.
//

import Foundation
import SwiftMCP
import PrototypeServerLib
import PrototypeExtensionsLib

@main
struct PrototypeRunner {
    static func main() async throws {
        let server = PrototypeServer()

        // Same-target extensions registered explicitly — works without the build plugin.
        PrototypeServer.Math.register(in: server)
        PrototypeServer.Strings.register(in: server)

        // Cross-target registration via the umbrella emitted by the plugin.
        SwiftMCPBootstrap_PrototypeExtensionsLib.register(in: server)

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
        try await invokeTool(server, "subtract",  args: ["a": .integer(10), "b": .integer(4)])

        print("\n=== Dispatching resources ===")
        try await invokeResource(server, URL(string: "info://build")!)
        try await invokeResource(server, URL(string: "strings://greet/Alice")!)
        try await invokeResource(server, URL(string: "calendar://today")!)

        print("\n=== Dispatching prompts ===")
        try await invokePrompt(server, "greetingPrompt",  args: ["name": .string("Bob")])
        try await invokePrompt(server, "summarizePrompt", args: ["text": .string("Lorem ipsum dolor sit amet.")])
        try await invokePrompt(server, "schedulingPrompt", args: ["person": .string("Carol")])
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
}
