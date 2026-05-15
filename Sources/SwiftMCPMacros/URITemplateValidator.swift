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
        if template.isEmpty {
            return URITemplateValidationResult(
                isValid: false,
                error: .invalidURITemplate(reason: "URI template cannot be empty"),
                level: 0,
                variables: []
            )
        }

        if !hasValidURIStructure(template) {
            let reason = "URI template must have a valid scheme "
                + "(e.g., 'http:', 'https:') or be a valid relative URI"
            return URITemplateValidationResult(
                isValid: false,
                error: .invalidURITemplate(reason: reason),
                level: 0,
                variables: []
            )
        }

        let expressionValidation = validateExpressions(in: template)
        if expressionValidation.error != nil {
            return expressionValidation
        }

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
        return validate(template).variables
    }
}

// Extension to add regex matching to String
extension String {
    func matches(_ pattern: String) -> Bool {
        return self.range(of: pattern, options: .regularExpression) != nil
    }
}
