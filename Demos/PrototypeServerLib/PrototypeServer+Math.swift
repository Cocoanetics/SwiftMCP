//
//  PrototypeServer+Math.swift — same-target extension #1.
//
//  Demonstrates a tools-only extension using the regular @MCPTool macro.
//

import SwiftMCP

// Name omitted — derived from filename "PrototypeServer+Math.swift" → "Math".
@MCPExtension
extension PrototypeServer {
    /// Add two integers.
    @MCPTool
    public func add(a: Int, b: Int) -> Int {
        a + b
    }

    /// Multiply two integers.
    @MCPTool
    public func multiply(a: Int, b: Int) -> Int {
        a * b
    }
}
