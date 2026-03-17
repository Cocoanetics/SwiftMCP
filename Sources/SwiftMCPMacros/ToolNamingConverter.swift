//
//  ToolNamingConverter.swift
//  SwiftMCPMacros
//
//  Minimal camelCase conversion for use in the macro module,
//  which cannot import SwiftMCP's NamingConverter.
//

/// Applies a tool-naming convention to a Swift function name at compile time.
enum ToolNamingConverter {

    /// Converts a lowerCamelCase identifier to snake_case.
    ///
    /// Handles acronym runs correctly:
    /// - `listWindows`      → `list_windows`
    /// - `getUserProfile`   → `get_user_profile`
    /// - `parseHTMLContent` → `parse_html_content`
    static func toSnakeCase(_ identifier: String) -> String {
        guard !identifier.isEmpty else { return identifier }
        let words = splitCamelCase(identifier)
        return words.map { $0.lowercased() }.joined(separator: "_")
    }

    /// Converts a lowerCamelCase identifier to PascalCase (UpperCamelCase).
    ///
    /// - `listWindows`    → `ListWindows`
    /// - `getUserProfile` → `GetUserProfile`
    static func toPascalCase(_ identifier: String) -> String {
        guard !identifier.isEmpty else { return identifier }
        let words = splitCamelCase(identifier)
        return words.map { $0.lowercased().capitalizingFirst() }.joined()
    }

    // MARK: - Private

    private static func splitCamelCase(_ string: String) -> [String] {
        guard !string.isEmpty else { return [] }

        var words: [String] = []
        var current = ""
        let chars = Array(string)

        for i in 0..<chars.count {
            let char = chars[i]

            if char.isUppercase {
                if current.isEmpty {
                    current.append(char)
                } else if current.last?.isUppercase == true {
                    let nextIsLower = (i + 1 < chars.count) && chars[i + 1].isLowercase
                    if nextIsLower {
                        words.append(current.lowercased())
                        current = String(char)
                    } else {
                        current.append(char)
                    }
                } else {
                    words.append(current.lowercased())
                    current = String(char)
                }
            } else {
                current.append(char)
            }
        }

        if !current.isEmpty {
            words.append(current.lowercased())
        }

        return words
    }
}

private extension String {
    func capitalizingFirst() -> String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
