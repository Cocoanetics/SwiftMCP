//
//  PrototypeServer.swift — primary @MCPServer declaration.
//
//  Declares one tool, one resource, and one prompt locally so the
//  @MCPServer macro emits the full MCPToolProviding / MCPResourceProviding /
//  MCPPromptProviding machinery. Extensions then contribute additional
//  tools, resources, and prompts via @MCPExtension.
//

import Foundation
import SwiftMCP

/// A demo server used to validate the extension-aggregation prototype.
@MCPServer(name: "prototype-server", version: "0.1")
public final class PrototypeServer: @unchecked Sendable {
    public init() {}

    /// Return a friendly greeting.
    @MCPTool
    public func greet(name: String) -> String {
        "Hello, \(name)!"
    }

    /// Returns server build info.
    @MCPResource("info://build")
    public func buildInfo() -> String {
        "PrototypeServer/0.1"
    }

    /// Greets the user as a prompt template.
    @MCPPrompt
    public func greetingPrompt(name: String) -> String {
        "Please greet \(name) warmly."
    }
}
