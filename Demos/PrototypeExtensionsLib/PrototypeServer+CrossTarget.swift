//
//  PrototypeServer+CrossTarget.swift
//
//  Cross-target extension. PrototypeServer is defined in PrototypeServerLib;
//  this target adds tools from a separate module — equivalent to a downstream
//  package contributing extensions.
//

import SwiftMCP
import PrototypeServerLib

extension PrototypeServer {
    /// Subtract b from a.
    @MCPExtensionTool
    public func subtract(a: Int, b: Int) -> Int {
        a - b
    }

    /// Echo a string back.
    @MCPExtensionTool
    public func echo(_ text: String) -> String {
        text
    }
}
