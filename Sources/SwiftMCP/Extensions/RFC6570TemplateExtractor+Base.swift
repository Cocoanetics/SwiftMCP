import Foundation

// MARK: - Base URL Extraction

extension RFC6570TemplateExtractor {
    /// Mutable cursor used while walking the template and URL in parallel.
    fileprivate struct BaseCursor {
        let templateBase: String
        let urlBase: String
        var templateIndex: String.Index
        var urlIndex: String.Index
    }

    /// Match the template's "base" (path) portion against the URL, populating
    /// `variables` with extracted values. Returns false when the literal
    /// portions of the template do not match the URL.
    func extractFromBase(
        urlBase: String,
        templateBase: String,
        variables: inout [String: String]
    ) -> Bool {
        var cursor = BaseCursor(
            templateBase: templateBase,
            urlBase: urlBase,
            templateIndex: templateBase.startIndex,
            urlIndex: urlBase.startIndex
        )

        while cursor.templateIndex < templateBase.endIndex {
            if templateBase[cursor.templateIndex] == "{" {
                guard let closingBrace = templateBase[cursor.templateIndex...]
                        .firstIndex(of: "}") else {
                    return false
                }
                if !consumeExpression(
                    cursor: &cursor,
                    closingBrace: closingBrace,
                    variables: &variables
                ) {
                    return false
                }
            } else {
                // Literal character - must match exactly
                guard cursor.urlIndex < urlBase.endIndex else { return false }
                if templateBase[cursor.templateIndex] != urlBase[cursor.urlIndex] {
                    return false
                }
                cursor.templateIndex = templateBase.index(after: cursor.templateIndex)
                cursor.urlIndex = urlBase.index(after: cursor.urlIndex)
            }
        }

        return finalizeBaseMatch(cursor: cursor)
    }

    /// Handle a single `{...}` expression while walking the template.
    private func consumeExpression(
        cursor: inout BaseCursor,
        closingBrace: String.Index,
        variables: inout [String: String]
    ) -> Bool {
        let templateBase = cursor.templateBase
        let urlBase = cursor.urlBase
        let exprStart = templateBase.index(after: cursor.templateIndex)
        let expressionContent = String(templateBase[exprStart..<closingBrace])
        let followingLiteral = literalFollowing(
            templateBase: templateBase,
            after: closingBrace
        )

        guard let extracted = extractAllVariablesFromExpression(
            expression: expressionContent,
            fromURL: urlBase,
            startingAt: cursor.urlIndex,
            followingLiteral: followingLiteral
        ) else {
            return false
        }

        for (name, value) in extracted.variables {
            variables[name] = value
        }

        cursor.templateIndex = templateBase.index(after: closingBrace)
        cursor.urlIndex = urlBase.index(cursor.urlIndex, offsetBy: extracted.consumedLength)
        return true
    }

    /// Returns the literal substring that follows the current expression in the
    /// template, up to the next expression or the end of the template.
    private func literalFollowing(
        templateBase: String,
        after closingBrace: String.Index
    ) -> String {
        let nextIndex = templateBase.index(after: closingBrace)
        guard nextIndex < templateBase.endIndex else { return "" }
        let rest = templateBase[nextIndex...]
        if let nextBrace = rest.firstIndex(of: "{") {
            return String(rest[..<nextBrace])
        } else {
            return String(rest)
        }
    }

    /// After walking through the template, verify the URL was fully consumed
    /// (or only the matching literal tail remains).
    private func finalizeBaseMatch(cursor: BaseCursor) -> Bool {
        var templateIndex = cursor.templateIndex
        var urlIndex = cursor.urlIndex
        let templateBase = cursor.templateBase
        let urlBase = cursor.urlBase

        if templateIndex == templateBase.endIndex {
            // Template is fully processed - URL should also be fully processed
            return urlIndex == urlBase.endIndex
        }

        // Remaining template characters must be literals that match the URL.
        while templateIndex < templateBase.endIndex && urlIndex < urlBase.endIndex {
            if templateBase[templateIndex] != urlBase[urlIndex] {
                return false
            }
            templateIndex = templateBase.index(after: templateIndex)
            urlIndex = urlBase.index(after: urlIndex)
        }

        return templateIndex == templateBase.endIndex
    }

    /// Dispatches expression extraction to the appropriate handler based on the
    /// expression operator.
    func extractAllVariablesFromExpression(
        expression: String,
        fromURL url: String,
        startingAt startIndex: String.Index,
        followingLiteral: String
    ) -> (variables: [String: String], consumedLength: Int)? {

        let (operatorType, variableSpecs) = parseExpression(expression)

        guard !variableSpecs.isEmpty else { return nil }

        switch operatorType {
        case .simple:
            return extractAllSimpleVariables(
                variables: variableSpecs,
                fromURL: url,
                startingAt: startIndex
            )
        case .reserved:
            return extractAllReservedVariables(
                variables: variableSpecs,
                fromURL: url,
                startingAt: startIndex,
                followingLiteral: followingLiteral
            )
        case .label:
            return extractAllLabelVariables(
                variables: variableSpecs,
                fromURL: url,
                startingAt: startIndex
            )
        case .pathSegment:
            return extractAllPathSegmentVariables(
                variables: variableSpecs,
                fromURL: url,
                startingAt: startIndex
            )
        case .pathStyle:
            return extractAllPathStyleVariables(
                variables: variableSpecs,
                fromURL: url,
                startingAt: startIndex
            )
        case .query, .queryContinuation:
            if let result = extractQueryVariable(
                variables: variableSpecs,
                fromURL: url,
                startingAt: startIndex
            ) {
                return ([result.variableName: result.value], result.consumedLength)
            }
            return nil
        case .fragment:
            // Fragments are handled separately in extractFragmentExpression
            return nil
        }
    }

    /// Dispatches single-variable extraction (used by the older path that
    /// retained the `ExtractedVariable` shape).
    func extractVariableValue(
        expression: String,
        fromURL url: String,
        startingAt startIndex: String.Index
    ) -> ExtractedVariable? {

        let (operatorType, variables) = parseExpression(expression)

        guard !variables.isEmpty else { return nil }

        switch operatorType {
        case .simple:
            return extractSimpleVariable(
                variables: variables,
                fromURL: url,
                startingAt: startIndex
            )
        case .reserved:
            return extractReservedVariable(
                variables: variables,
                fromURL: url,
                startingAt: startIndex
            )
        case .label:
            return extractLabelVariable(
                variables: variables,
                fromURL: url,
                startingAt: startIndex
            )
        case .pathSegment:
            return extractPathSegmentVariable(
                variables: variables,
                fromURL: url,
                startingAt: startIndex
            )
        case .pathStyle:
            return extractPathStyleVariable(
                variables: variables,
                fromURL: url,
                startingAt: startIndex
            )
        case .query, .queryContinuation:
            return extractQueryVariable(
                variables: variables,
                fromURL: url,
                startingAt: startIndex
            )
        case .fragment:
            // Fragments are handled separately in extractFragmentExpression
            return nil
        }
    }
}
