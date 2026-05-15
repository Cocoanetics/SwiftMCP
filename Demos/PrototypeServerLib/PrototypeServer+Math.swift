//
//  PrototypeServer+Math.swift — same-target extension #1.
//
//  Demonstrates a tools-only extension using the regular @MCPTool macro.
//

import SwiftMCP

// swiftlint:disable identifier_name
// Parameters `a`, `b` mirror the canonical MCP tutorial math example.

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
// swiftlint:enable identifier_name
