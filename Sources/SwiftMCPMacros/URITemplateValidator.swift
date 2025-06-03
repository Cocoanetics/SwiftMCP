//
//  URITemplateValidator.swift
//  SwiftMCPMacros
//
//  Created by SwiftMCP on $(date).
//

import Foundation

/// Result of URI template validation
struct URITemplateValidationResult {
    let isValid: Bool
    let error: MCPResourceDiagnostic?
    let level: Int // RFC 6570 level (1-4)
    let variables: [String] // Extracted variable names
}

/// URI Template validator conforming to RFC 6570
struct URITemplateValidator {

    /// Validates a URI template according to RFC 6570
    static func validate(_ template: String) -> URITemplateValidationResult {
        // Check for empty template
        if template.isEmpty {
            return URITemplateValidationResult(
                isValid: false,
                error: .invalidURITemplate(reason: "URI template cannot be empty"),
                level: 0,
                variables: []
            )
        }

        // Check for basic URI structure - must have a scheme or be relative
        if !hasValidURIStructure(template) {
            return URITemplateValidationResult(
                isValid: false,
                error: .invalidURITemplate(reason: "URI template must have a valid scheme (e.g., 'http:', 'https:') or be a valid relative URI"),
                level: 0,
                variables: []
            )
        }

        // Validate expressions and extract variables
        let expressionValidation = validateExpressions(in: template)
        if let error = expressionValidation.error {
            return URITemplateValidationResult(
                isValid: false,
                error: error,
                level: expressionValidation.level,
                variables: expressionValidation.variables
            )
        }

        // Validate literal characters
        if let literalError = validateLiteralCharacters(template) {
            return URITemplateValidationResult(
                isValid: false,
                error: literalError,
                level: 0,
                variables: expressionValidation.variables
            )
        }

        return URITemplateValidationResult(
            isValid: true,
            error: nil,
            level: expressionValidation.level,
            variables: expressionValidation.variables
        )
    }

    /// Extracts variable names from a URI template
    static func extractVariables(from template: String) -> [String] {
        let result = validate(template)
        return result.variables
    }

    // MARK: - Private validation methods

    /// Checks if the template has a valid URI structure
    private static func hasValidURIStructure(_ template: String) -> Bool {
        // Remove expressions for basic structure validation
        let withoutExpressions = template.replacingOccurrences(
            of: "\\{[^}]*\\}",
            with: "PLACEHOLDER",
            options: .regularExpression
        )

        // First, check if it looks like an invalid absolute URI
        // If it contains "://" but doesn't have a valid scheme, it's invalid
        if withoutExpressions.contains("://") {
            // Must have a valid scheme before "://"
            return withoutExpressions.matches("^[a-zA-Z][a-zA-Z0-9+.-]*://")
        }

        // Check if it looks like a scheme-only URI (contains ":" but not "://")
        if withoutExpressions.contains(":") && !withoutExpressions.contains("://") {
            // Must have a valid scheme before ":"
            return withoutExpressions.matches("^[a-zA-Z][a-zA-Z0-9+.-]*:")
        }

        // Check for valid relative URI patterns
        if withoutExpressions.hasPrefix("/") || // absolute path
           withoutExpressions.hasPrefix("?") || // query only
           withoutExpressions.hasPrefix("#") { // fragment only
            return true
        }

        // For relative paths, be more restrictive
        // Must start with a letter, digit, or certain safe characters, but not look like an invalid scheme
        if withoutExpressions.matches("^[a-zA-Z0-9._~-]") {
            // Additional check: if it contains ":" early on, it might be an invalid scheme
            // Look for ":" in the first few characters which would indicate a scheme attempt
            if let colonIndex = withoutExpressions.firstIndex(of: ":") {
                let distanceToColon = withoutExpressions.distance(from: withoutExpressions.startIndex, to: colonIndex)
                if distanceToColon < 10 { // Reasonable scheme length limit
                    // This looks like an attempted scheme, so validate it properly
                    let potentialScheme = String(withoutExpressions[..<colonIndex])
                    return potentialScheme.matches("^[a-zA-Z][a-zA-Z0-9+.-]*$")
                }
            }
            return true
        }

        return false
    }

    /// Validates expressions in the URI template
    private static func validateExpressions(in template: String) -> URITemplateValidationResult {
        var level = 1
        var braceDepth = 0
        var i = template.startIndex
        var allVariables: [String] = []

        while i < template.endIndex {
            let char = template[i]

            if char == "{" {
                braceDepth += 1
                if braceDepth > 1 {
                    return URITemplateValidationResult(
                        isValid: false,
                        error: .invalidURITemplate(reason: "Nested expressions are not allowed - expressions cannot contain '{' or '}'"),
                        level: 0,
                        variables: allVariables
                    )
                }

                // Find the closing brace
                let expressionStart = template.index(after: i)
                guard let closingBrace = template[expressionStart...].firstIndex(of: "}") else {
                    return URITemplateValidationResult(
                        isValid: false,
                        error: .invalidURITemplate(reason: "Unclosed expression - missing '}' for expression starting at position \(template.distance(from: template.startIndex, to: i))"),
                        level: 0,
                        variables: allVariables
                    )
                }

                let expression = String(template[expressionStart..<closingBrace])
                let expressionValidation = validateSingleExpression(expression)
                if let error = expressionValidation.error {
                    return URITemplateValidationResult(
                        isValid: false,
                        error: error,
                        level: expressionValidation.level,
                        variables: allVariables
                    )
                }

                level = max(level, expressionValidation.level)
                allVariables.append(contentsOf: expressionValidation.variables)
                i = template.index(after: closingBrace)
                braceDepth = 0

            } else if char == "}" {
                    return URITemplateValidationResult(
                    isValid: false,
                    error: .invalidURITemplate(reason: "Unexpected '}' - closing brace without matching opening brace"),
                    level: 0,
                    variables: allVariables
                )
                } else {
                    i = template.index(after: i)
                }
        }

        if braceDepth > 0 {
            return URITemplateValidationResult(
                isValid: false,
                error: .invalidURITemplate(reason: "Unclosed expression - missing '}' at end of template"),
                level: 0,
                variables: allVariables
            )
        }

        return URITemplateValidationResult(isValid: true, error: nil, level: level, variables: allVariables)
    }

    /// Validates a single expression (content between braces)
    private static func validateSingleExpression(_ expression: String) -> URITemplateValidationResult {
        if expression.isEmpty {
            return URITemplateValidationResult(
                isValid: false,
                error: .invalidURITemplate(reason: "Empty expression '{}' is not allowed"),
                level: 0,
                variables: []
            )
        }

        var level = 1
        var expr = expression

        // Check for operator
        let firstChar = expr.first!
        let operators: [Character: Int] = [
            "+": 2, "#": 2,           // Level 2
            ".": 3, "/": 3, ";": 3, "?": 3, "&": 3,  // Level 3
            "=": 4, ",": 4, "!": 4, "@": 4, "|": 4   // Reserved for future (Level 4+)
        ]

        if let opLevel = operators[firstChar] {
            if opLevel >= 4 {
                return URITemplateValidationResult(
                    isValid: false,
                    error: .invalidURITemplate(reason: "Operator '\(firstChar)' is reserved for future extensions and not currently supported"),
                    level: opLevel,
                    variables: []
                )
            }
            level = max(level, opLevel)
            expr = String(expr.dropFirst())
        }

        // Validate variable list
        let variables = expr.split(separator: ",")
        if variables.isEmpty {
            return URITemplateValidationResult(
                isValid: false,
                error: .invalidURITemplate(reason: "Expression must contain at least one variable name"),
                level: 0,
                variables: []
            )
        }

        if variables.count > 1 {
            level = max(level, 3) // Multiple variables require Level 3
        }

        var extractedVariables: [String] = []

        for variable in variables {
            let varValidation = validateVariable(String(variable))
            if let error = varValidation.error {
                return URITemplateValidationResult(
                    isValid: false,
                    error: error,
                    level: varValidation.level,
                    variables: extractedVariables
                )
            }
            level = max(level, varValidation.level)
            extractedVariables.append(contentsOf: varValidation.variables)
        }

        return URITemplateValidationResult(isValid: true, error: nil, level: level, variables: extractedVariables)
    }

    /// Validates a single variable specification
    private static func validateVariable(_ variable: String) -> URITemplateValidationResult {
        if variable.isEmpty {
            return URITemplateValidationResult(
                isValid: false,
                error: .invalidURITemplate(reason: "Variable name cannot be empty"),
                level: 0,
                variables: []
            )
        }

        var level = 1
        var varName = variable

        // Check for explode modifier (*)
        if varName.hasSuffix("*") {
            level = max(level, 4)
            varName = String(varName.dropLast())
        }

        // Check for prefix modifier (:digits)
        if let colonIndex = varName.lastIndex(of: ":") {
            let prefixPart = varName[varName.index(after: colonIndex)...]
            if prefixPart.isEmpty {
                return URITemplateValidationResult(
                    isValid: false,
                    error: .invalidURITemplate(reason: "Prefix modifier ':' must be followed by a positive integer"),
                    level: 0,
                    variables: []
                )
            }

            guard let prefixLength = Int(prefixPart), prefixLength > 0, prefixLength < 10000 else {
                return URITemplateValidationResult(
                    isValid: false,
                    error: .invalidURITemplate(reason: "Prefix length must be a positive integer less than 10000, got '\(prefixPart)'"),
                    level: 0,
                    variables: []
                )
            }

            level = max(level, 4)
            varName = String(varName[..<colonIndex])
        }

        // Validate variable name characters
        if !isValidVariableName(varName) {
            return URITemplateValidationResult(
                isValid: false,
                error: .invalidURITemplate(reason: "Invalid variable name '\(varName)' - must contain only letters, digits, underscore, dots, and percent-encoded characters"),
                level: 0,
                variables: []
            )
        }

        return URITemplateValidationResult(isValid: true, error: nil, level: level, variables: [varName])
    }

    /// Validates that a variable name contains only allowed characters
    private static func isValidVariableName(_ name: String) -> Bool {
        // varchar = ALPHA / DIGIT / "_" / pct-encoded
        // varname = varchar *( ["."] varchar )
        // Variable names must start with a letter or underscore, not a digit

        let allowedPattern = "^[a-zA-Z_][a-zA-Z0-9_]*(\\.[a-zA-Z_][a-zA-Z0-9_]*)*$"
        return name.matches(allowedPattern) && !name.isEmpty
    }

    /// Validates literal characters in the template
    private static func validateLiteralCharacters(_ template: String) -> MCPResourceDiagnostic? {
        // Remove expressions to check only literals
        let literalsOnly = template.replacingOccurrences(
            of: "\\{[^}]*\\}",
            with: "",
            options: .regularExpression
        )

        // Check for disallowed characters in literals
        let disallowedChars: Set<Character> = ["<", ">", "\\", "^", "`", "{", "}", "|", "\"", "'"]

        for char in literalsOnly {
            if disallowedChars.contains(char) {
                return .invalidURITemplate(reason: "Invalid character '\(char)' in URI template - characters like <, >, \\, ^, `, {, }, |, \", ' are not allowed outside expressions")
            }

            // Check for control characters and spaces
            if char.isASCII && (char.asciiValue! < 0x21 || char.asciiValue == 0x7F) && char != " " {
                return .invalidURITemplate(reason: "Control character (ASCII \(char.asciiValue!)) is not allowed in URI template")
            }
        }

        return nil
    }
}

// Extension to add regex matching to String
extension String {
    func matches(_ pattern: String) -> Bool {
        return self.range(of: pattern, options: .regularExpression) != nil
    }
} 