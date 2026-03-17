import Foundation

/// Converts identifiers between naming conventions.
///
/// Supports lowerCamelCase, UpperCamelCase (PascalCase), and snake_case.
/// Handles acronym runs correctly (e.g., `HTMLParser` ↔ `htmlParser` ↔ `html_parser`).
public enum NamingConverter {

    /// The supported naming conventions.
    public enum Convention: Equatable {
        /// lowerCamelCase (e.g., `buildProject`, `htmlParser`)
        case lowerCamelCase
        /// UpperCamelCase / PascalCase (e.g., `BuildProject`, `HTMLParser`)
        case upperCamelCase
        /// snake_case (e.g., `build_project`, `html_parser`)
        case snakeCase
    }

    // MARK: - Public API

    /// Converts an identifier from one naming convention to another.
    ///
    /// - Parameters:
    ///   - identifier: The input identifier string.
    ///   - source: The convention of the input (or `nil` to auto-detect).
    ///   - target: The desired output convention.
    /// - Returns: The converted identifier.
    public static func convert(
        _ identifier: String,
        from source: Convention? = nil,
        to target: Convention
    ) -> String {
        guard !identifier.isEmpty else { return identifier }

        let detected = source ?? detect(identifier)

        // Return as-is when already in the target convention
        if detected == target { return identifier }

        let words = splitIntoWords(identifier, convention: detected)

        switch target {
        case .lowerCamelCase:
            return joinLowerCamelCase(words)
        case .upperCamelCase:
            return joinUpperCamelCase(words)
        case .snakeCase:
            return joinSnakeCase(words)
        }
    }

    /// Converts a PascalCase or snake_case identifier to lowerCamelCase.
    public static func toLowerCamelCase(_ identifier: String) -> String {
        convert(identifier, to: .lowerCamelCase)
    }

    /// Converts a lowerCamelCase or snake_case identifier to UpperCamelCase (PascalCase).
    public static func toUpperCamelCase(_ identifier: String) -> String {
        convert(identifier, to: .upperCamelCase)
    }

    /// Converts a camelCase identifier to snake_case.
    public static func toSnakeCase(_ identifier: String) -> String {
        convert(identifier, to: .snakeCase)
    }

    /// Auto-detects the naming convention of an identifier.
    public static func detect(_ identifier: String) -> Convention {
        if identifier.contains("_") {
            return .snakeCase
        }
        if let first = identifier.first, first.isUppercase {
            return .upperCamelCase
        }
        return .lowerCamelCase
    }

    // MARK: - Word Splitting

    /// Splits an identifier into its constituent words.
    private static func splitIntoWords(_ identifier: String, convention: Convention) -> [String] {
        switch convention {
        case .snakeCase:
            return identifier
                .split(separator: "_")
                .map { String($0).lowercased() }
                .filter { !$0.isEmpty }

        case .lowerCamelCase, .upperCamelCase:
            return splitCamelCase(identifier)
        }
    }

    /// Splits a camelCase or PascalCase identifier into lowercase words.
    ///
    /// Handles acronym runs correctly:
    /// - `HTMLParser`   → `["html", "parser"]`
    /// - `XcodeRead`    → `["xcode", "read"]`
    /// - `XcodeMV`      → `["xcode", "mv"]`
    /// - `XcodeLS`      → `["xcode", "ls"]`
    /// - `buildProject` → `["build", "project"]`
    /// - `getURLForRequest` → `["get", "url", "for", "request"]`
    private static func splitCamelCase(_ string: String) -> [String] {
        guard !string.isEmpty else { return [] }

        var words: [String] = []
        var current = ""
        let chars = Array(string)

        for i in 0..<chars.count {
            let char = chars[i]

            if char.isUppercase {
                if current.isEmpty {
                    // Start of string or new word
                    current.append(char)
                } else if current.last?.isUppercase == true {
                    // Continuing an uppercase run (acronym)
                    // Check if this is the last uppercase before a lowercase transition
                    let nextIsLower = (i + 1 < chars.count) && chars[i + 1].isLowercase
                    if nextIsLower {
                        // This uppercase starts a new word (end of acronym)
                        words.append(current.lowercased())
                        current = String(char)
                    } else {
                        // Still in acronym
                        current.append(char)
                    }
                } else {
                    // Transition from lowercase to uppercase → new word
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

    // MARK: - Word Joining

    /// Joins words as lowerCamelCase: first word lowercase, rest capitalized.
    private static func joinLowerCamelCase(_ words: [String]) -> String {
        guard let first = words.first else { return "" }
        let rest = words.dropFirst().map { $0.capitalizingFirstLetter() }
        return first.lowercased() + rest.joined()
    }

    /// Joins words as UpperCamelCase: all words capitalized.
    private static func joinUpperCamelCase(_ words: [String]) -> String {
        words.map { $0.capitalizingFirstLetter() }.joined()
    }

    /// Joins words as snake_case: all lowercase, separated by underscores.
    private static func joinSnakeCase(_ words: [String]) -> String {
        words.map { $0.lowercased() }.joined(separator: "_")
    }
}

// MARK: - String Helpers

private extension String {
    func capitalizingFirstLetter() -> String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
