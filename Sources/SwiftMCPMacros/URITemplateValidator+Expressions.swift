//
//  URITemplateValidator+Expressions.swift
//  SwiftMCPMacros
//
//  RFC 6570 expression and variable-spec validation.
//

import Foundation

extension URITemplateValidator {

    /// Validates expressions in the URI template
    static func validateExpressions(in template: String) -> URITemplateValidationResult {
        var level = 1
        var braceDepth = 0
        var cursor = template.startIndex
        var allVariables: [String] = []

        while cursor < template.endIndex {
            let char = template[cursor]
            if char == "{" {
                let stepResult = stepThroughBrace(
                    in: template,
                    openingBrace: cursor,
                    braceDepth: &braceDepth,
                    accumulatedVariables: allVariables
                )
                switch stepResult {
                case .failure(let validationResult):
                    return validationResult
                case .success(let outcome):
                    level = max(level, outcome.level)
                    allVariables.append(contentsOf: outcome.variables)
                    cursor = outcome.nextCursor
                }
            } else if char == "}" {
                return URITemplateValidationResult(
                    isValid: false,
                    error: .invalidURITemplate(reason: "Unexpected '}' - closing brace without matching opening brace"),
                    level: 0,
                    variables: allVariables
                )
            } else {
                cursor = template.index(after: cursor)
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

    /// Handles the step taken at an opening brace: rejects nested
    /// expressions, otherwise consumes the expression up to its closing
    /// brace and resets the brace depth.
    private static func stepThroughBrace(
        in template: String,
        openingBrace: String.Index,
        braceDepth: inout Int,
        accumulatedVariables: [String]
    ) -> ExpressionResult {
        braceDepth += 1
        if braceDepth > 1 {
            let reason = "Nested expressions are not allowed - "
                + "expressions cannot contain '{' or '}'"
            return .failure(URITemplateValidationResult(
                isValid: false,
                error: .invalidURITemplate(reason: reason),
                level: 0,
                variables: accumulatedVariables
            ))
        }

        let result = consumeExpression(
            in: template,
            openingBrace: openingBrace,
            accumulatedVariables: accumulatedVariables
        )
        if case .success = result {
            braceDepth = 0
        }
        return result
    }

    private struct ExpressionOutcome {
        let level: Int
        let variables: [String]
        let nextCursor: String.Index
    }

    private enum ExpressionResult {
        case success(ExpressionOutcome)
        case failure(URITemplateValidationResult)
    }

    /// Locates the closing brace for an expression that opens at
    /// `openingBrace`, validates the content, and reports the position
    /// immediately past the closing brace.
    private static func consumeExpression(
        in template: String,
        openingBrace: String.Index,
        accumulatedVariables: [String]
    ) -> ExpressionResult {
        let expressionStart = template.index(after: openingBrace)
        guard let closingBrace = template[expressionStart...].firstIndex(of: "}") else {
            let position = template.distance(from: template.startIndex, to: openingBrace)
            let reason = "Unclosed expression - missing '}' for "
                + "expression starting at position \(position)"
            return .failure(URITemplateValidationResult(
                isValid: false,
                error: .invalidURITemplate(reason: reason),
                level: 0,
                variables: accumulatedVariables
            ))
        }

        let expression = String(template[expressionStart..<closingBrace])
        let expressionValidation = validateSingleExpression(expression)
        if expressionValidation.error != nil {
            return .failure(URITemplateValidationResult(
                isValid: false,
                error: expressionValidation.error,
                level: expressionValidation.level,
                variables: accumulatedVariables
            ))
        }

        return .success(ExpressionOutcome(
            level: expressionValidation.level,
            variables: expressionValidation.variables,
            nextCursor: template.index(after: closingBrace)
        ))
    }

    /// Validates a single expression (content between braces)
    static func validateSingleExpression(_ expression: String) -> URITemplateValidationResult {
        if expression.isEmpty {
            return URITemplateValidationResult(
                isValid: false,
                error: .invalidURITemplate(reason: "Empty expression '{}' is not allowed"),
                level: 0,
                variables: []
            )
        }

        let operatorStripResult = stripOperator(expression)
        if let failure = operatorStripResult.failure { return failure }
        let expr = operatorStripResult.expr
        var level = operatorStripResult.level

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

    /// Result of inspecting the leading operator of an expression: the
    /// remaining expression text, the inferred level, and an optional
    /// failure result for reserved operators.
    private struct OperatorStripResult {
        let expr: String
        let level: Int
        let failure: URITemplateValidationResult?
    }

    /// Inspects the leading operator (if any) and returns the remaining
    /// expression text, the inferred level, and an optional failure result
    /// for reserved operators.
    private static func stripOperator(
        _ expression: String
    ) -> OperatorStripResult {
        var level = 1
        var expr = expression

        let firstChar = expr.first!
        let operators: [Character: Int] = [
            "+": 2, "#": 2,           // Level 2
            ".": 3, "/": 3, ";": 3, "?": 3, "&": 3,  // Level 3
            "=": 4, ",": 4, "!": 4, "@": 4, "|": 4   // Reserved for future (Level 4+)
        ]

        if let opLevel = operators[firstChar] {
            if opLevel >= 4 {
                let reason = "Operator '\(firstChar)' is reserved for "
                    + "future extensions and not currently supported"
                let failure = URITemplateValidationResult(
                    isValid: false,
                    error: .invalidURITemplate(reason: reason),
                    level: opLevel,
                    variables: []
                )
                return OperatorStripResult(expr: expr, level: level, failure: failure)
            }
            level = max(level, opLevel)
            expr = String(expr.dropFirst())
        }

        return OperatorStripResult(expr: expr, level: level, failure: nil)
    }

    /// Validates a single variable specification
    static func validateVariable(_ variable: String) -> URITemplateValidationResult {
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
            switch validatePrefixModifier(in: varName, colonIndex: colonIndex) {
            case .failure(let result):
                return result
            case .success(let stripped):
                level = max(level, 4)
                varName = stripped
            }
        }

        // Validate variable name characters
        if !isValidVariableName(varName) {
            let reason = "Invalid variable name '\(varName)' - must contain only letters, "
                + "digits, underscore, dots, and percent-encoded characters"
            return URITemplateValidationResult(
                isValid: false,
                error: .invalidURITemplate(reason: reason),
                level: 0,
                variables: []
            )
        }

        return URITemplateValidationResult(isValid: true, error: nil, level: level, variables: [varName])
    }

    private enum PrefixResult {
        case success(String) // variable name with the prefix stripped
        case failure(URITemplateValidationResult)
    }

    private static func validatePrefixModifier(
        in varName: String,
        colonIndex: String.Index
    ) -> PrefixResult {
        let prefixPart = varName[varName.index(after: colonIndex)...]
        if prefixPart.isEmpty {
            return .failure(URITemplateValidationResult(
                isValid: false,
                error: .invalidURITemplate(reason: "Prefix modifier ':' must be followed by a positive integer"),
                level: 0,
                variables: []
            ))
        }

        guard let prefixLength = Int(prefixPart), prefixLength > 0, prefixLength < 10000 else {
            let reason = "Prefix length must be a positive integer "
                + "less than 10000, got '\(prefixPart)'"
            return .failure(URITemplateValidationResult(
                isValid: false,
                error: .invalidURITemplate(reason: reason),
                level: 0,
                variables: []
            ))
        }

        _ = prefixLength
        return .success(String(varName[..<colonIndex]))
    }

    /// Validates that a variable name contains only allowed characters
    static func isValidVariableName(_ name: String) -> Bool {
        // varchar = ALPHA / DIGIT / "_" / pct-encoded
        // varname = varchar *( ["."] varchar )
        // Variable names must start with a letter or underscore, not a digit
        let allowedPattern = "^[a-zA-Z_][a-zA-Z0-9_]*(\\.[a-zA-Z_][a-zA-Z0-9_]*)*$"
        return name.matches(allowedPattern) && !name.isEmpty
    }
}
