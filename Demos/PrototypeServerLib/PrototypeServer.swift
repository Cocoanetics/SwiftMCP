//
//  PrototypeServer.swift — primary @MCPServer declaration.
//
//  Declares only one tool locally. All resources and prompts on this
//  server come from `@MCPExtension`-annotated extensions, validating
//  that the macro emits the resource and prompt machinery even when the
//  primary type declares none.
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
}
