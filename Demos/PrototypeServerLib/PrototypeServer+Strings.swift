//
//  PrototypeServer+Strings.swift — same-target extension #2.
//

import SwiftMCP

@MCPExtension("Strings")
extension PrototypeServer {
    /// Uppercase a string.
    @MCPExtensionTool
    public func shout(_ text: String) -> String {
        text.uppercased()
    }
}
