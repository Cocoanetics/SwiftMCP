//
//  PrototypeServer+Math.swift — same-target extension #1.
//

import SwiftMCP

extension PrototypeServer {
    /// Add two integers.
    @MCPExtensionTool
    public func add(a: Int, b: Int) -> Int {
        a + b
    }

    /// Multiply two integers.
    @MCPExtensionTool
    public func multiply(a: Int, b: Int) -> Int {
        a * b
    }
}
