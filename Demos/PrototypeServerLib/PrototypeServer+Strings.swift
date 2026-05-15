//
//  PrototypeServer+Strings.swift — same-target extension #2.
//
//  Mixes a tool, a resource, and a prompt in a single extension to exercise
//  all three contribution kinds.
//

import Foundation
import SwiftMCP

// Name omitted — derived from filename "PrototypeServer+Strings.swift" → "Strings".
@MCPExtension
extension PrototypeServer {
    /// Uppercase a string.
    @MCPTool
    public func shout(_ text: String) -> String {
        text.uppercased()
    }

    /// Echo a templated greeting back as a resource.
    @MCPResource("strings://greet/{name}")
    public func greetingResource(name: String) -> String {
        "Greetings, \(name)!"
    }

    /// Build a prompt asking the model to summarize a piece of text.
    @MCPPrompt
    public func summarizePrompt(text: String) -> String {
        "Summarize the following in one sentence: \(text)"
    }
}
