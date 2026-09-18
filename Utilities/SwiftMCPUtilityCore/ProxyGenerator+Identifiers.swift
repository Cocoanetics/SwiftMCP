import Foundation
import SwiftMCP

extension ProxyGenerator {
    static func pascalCase(_ string: String) -> String {
        let parts = string.split { !$0.isLetter && !$0.isNumber }
        let joined = parts.map { part -> String in
            guard let first = part.first else { return "" }
            return String(first).uppercased() + part.dropFirst()
        }.joined()
        return joined.isEmpty ? "MCPServer" : joined
    }

    static func swiftIdentifier(from raw: String, lowerCamel: Bool) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if isValidIdentifier(trimmed) {
            return reservedKeywords.contains(trimmed) ? "\(trimmed)_" : trimmed
        }

        let parts = trimmed.split { !$0.isLetter && !$0.isNumber }
        if parts.isEmpty {
            return "value"
        }

        let first = String(parts[0])
        let rest = parts.dropFirst().map { part -> String in
            let value = String(part)
            guard let firstChar = value.first else { return value }
            return String(firstChar).uppercased() + value.dropFirst()
        }
        var combined = ([first] + rest).joined()

        if !lowerCamel, let firstChar = combined.first {
            combined = String(firstChar).uppercased() + combined.dropFirst()
        }

        if let firstChar = combined.first, firstChar.isNumber {
            combined = "_" + combined
        }

        if reservedKeywords.contains(combined) {
            combined += "_"
        }

        return combined
    }

    /// Builds the Swift label for a parameter the server declared as `raw`.
    ///
    /// The wire key is unaffected; this only changes how the label reads in Swift.
    static func parameterIdentifier(from raw: String, naming: ParameterNaming) -> String {
        let converted: String
        switch naming {
        case .verbatim:
            converted = raw
        case .lowerCamelCase:
            converted = NamingConverter.toLowerCamelCase(raw)
        case .snakeCase:
            converted = NamingConverter.toSnakeCase(raw)
        }
        return swiftIdentifier(from: converted, lowerCamel: true)
    }

    static func isValidIdentifier(_ value: String) -> Bool {
        guard let first = value.first else {
            return false
        }
        guard first.isLetter || first == "_" else {
            return false
        }
        for character in value.dropFirst() where !(character.isLetter || character.isNumber || character == "_") {
            return false
        }
        return true
    }

    static func escapeSwiftString(_ value: String) -> String {
        var escaped = value
        escaped = escaped.replacingOccurrences(of: "\\", with: "\\\\")
        escaped = escaped.replacingOccurrences(of: "\"", with: "\\\"")
        escaped = escaped.replacingOccurrences(of: "\n", with: "\\n")
        escaped = escaped.replacingOccurrences(of: "\r", with: "\\r")
        escaped = escaped.replacingOccurrences(of: "\t", with: "\\t")
        return escaped
    }

    static let reservedKeywords: Set<String> = [
        "associatedtype", "class", "deinit", "enum", "extension", "fileprivate",
        "func", "import", "init", "inout", "internal", "let", "open", "operator",
        "private", "protocol", "public", "static", "struct", "subscript", "typealias",
        "var", "break", "case", "continue", "default", "defer", "do", "else", "fallthrough",
        "for", "guard", "if", "in", "repeat", "return", "switch", "where", "while",
        "as", "catch", "false", "is", "nil", "rethrows", "super", "self", "Self",
        "throw", "throws", "true", "try", "Any"
    ]
}
