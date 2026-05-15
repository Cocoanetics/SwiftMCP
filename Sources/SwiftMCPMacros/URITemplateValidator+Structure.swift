//
//  URITemplateValidator+Structure.swift
//  SwiftMCPMacros
//
//  Validation helpers for the overall URI structure (scheme / relative-URI
//  shape) and for literal characters between RFC 6570 expressions.
//

import Foundation

extension URITemplateValidator {

    /// Checks if the template has a valid URI structure
    static func hasValidURIStructure(_ template: String) -> Bool {
        let withoutExpressions = template.replacingOccurrences(
            of: "\\{[^}]*\\}",
            with: "PLACEHOLDER",
            options: .regularExpression
        )

        // If it contains "://" we must have a valid scheme before it.
        if withoutExpressions.contains("://") {
            return withoutExpressions.matches("^[a-zA-Z][a-zA-Z0-9+.-]*://")
        }

        // A scheme without authority (e.g. "mailto:") still requires a valid
        // scheme prefix before the colon.
        if withoutExpressions.contains(":") {
            return withoutExpressions.matches("^[a-zA-Z][a-zA-Z0-9+.-]*:")
        }

        // Absolute paths and query/fragment-only references are always
        // permitted relative URIs.
        if withoutExpressions.hasPrefix("/")
            || withoutExpressions.hasPrefix("?")
            || withoutExpressions.hasPrefix("#") {
            return true
        }

        return hasValidRelativePrefix(withoutExpressions)
    }

    /// Validates the prefix of a relative URI that doesn't start with `/`,
    /// `?`, or `#`. Catches strings that look like attempted but invalid
    /// schemes.
    private static func hasValidRelativePrefix(_ value: String) -> Bool {
        guard value.matches("^[a-zA-Z0-9._~-]") else { return false }

        // A colon near the start might indicate an attempted scheme — if
        // present, the prefix must satisfy scheme rules.
        if let colonIndex = value.firstIndex(of: ":") {
            let distanceToColon = value.distance(from: value.startIndex, to: colonIndex)
            if distanceToColon < 10 { // Reasonable scheme length limit
                let potentialScheme = String(value[..<colonIndex])
                return potentialScheme.matches("^[a-zA-Z][a-zA-Z0-9+.-]*$")
            }
        }
        return true
    }

    /// Validates literal characters in the template
    static func validateLiteralCharacters(_ template: String) -> MCPResourceDiagnostic? {
        let literalsOnly = template.replacingOccurrences(
            of: "\\{[^}]*\\}",
            with: "",
            options: .regularExpression
        )

        let disallowedChars: Set<Character> = ["<", ">", "\\", "^", "`", "{", "}", "|", "\"", "'"]

        for char in literalsOnly {
            if disallowedChars.contains(char) {
                let reason = "Invalid character '\(char)' in URI template - "
                    + "characters like <, >, \\, ^, `, {, }, |, \", ' are not allowed "
                    + "outside expressions"
                return .invalidURITemplate(reason: reason)
            }

            if char.isASCII && (char.asciiValue! < 0x21 || char.asciiValue == 0x7F) && char != " " {
                let reason = "Control character (ASCII \(char.asciiValue!)) "
                    + "is not allowed in URI template"
                return .invalidURITemplate(reason: reason)
            }
        }

        return nil
    }
}
