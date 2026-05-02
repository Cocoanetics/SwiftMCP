//
//  PrototypeServer.swift — primary @MCPServer declaration.
//

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
