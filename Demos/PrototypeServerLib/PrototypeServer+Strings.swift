//
//  PrototypeServer+Strings.swift — same-target extension #2.
//

import SwiftMCP

extension PrototypeServer {
    /// Uppercase a string.
    @MCPExtensionTool
    public func shout(_ text: String) -> String {
        text.uppercased()
    }
}
