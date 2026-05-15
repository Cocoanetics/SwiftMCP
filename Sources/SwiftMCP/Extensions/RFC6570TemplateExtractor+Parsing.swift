import Foundation

// MARK: - Expression & Query Parsing

extension RFC6570TemplateExtractor {
    func parseExpression(_ expression: String) -> (ExpressionOperator, [VariableSpec]) {
        var expr = expression
        var operatorType: ExpressionOperator = .simple

        // Check for operator prefix
        if let firstChar = expr.first {
            switch firstChar {
            case "+":
                operatorType = .reserved
                expr = String(expr.dropFirst())
            case "#":
                operatorType = .fragment
                expr = String(expr.dropFirst())
            case ".":
                operatorType = .label
                expr = String(expr.dropFirst())
            case "/":
                operatorType = .pathSegment
                expr = String(expr.dropFirst())
            case ";":
                operatorType = .pathStyle
                expr = String(expr.dropFirst())
            case "?":
                operatorType = .query
                expr = String(expr.dropFirst())
            case "&":
                operatorType = .queryContinuation
                expr = String(expr.dropFirst())
            default:
                break
            }
        }

        // Parse variables
        let variableSpecs = expr.split(separator: ",").compactMap { parseVariableSpec(String($0)) }

        return (operatorType, variableSpecs)
    }

    func parseVariableSpec(_ spec: String) -> VariableSpec? {
        guard !spec.isEmpty else { return nil }

        var name = spec
        var modifier: VariableModifier = .none

        // Check for explode modifier
        if name.hasSuffix("*") {
            modifier = .explode
            name = String(name.dropLast())
        }

        // Check for prefix modifier
        if let colonIndex = name.lastIndex(of: ":") {
            let prefixPart = name[name.index(after: colonIndex)...]
            if let prefixLength = Int(prefixPart), prefixLength > 0 {
                modifier = .prefix(prefixLength)
                name = String(name[..<colonIndex])
            }
        }

        guard !name.isEmpty else { return nil }
        return VariableSpec(name: name, modifier: modifier)
    }

    func parseQueryParameters(_ query: String) -> [String: String] {
        var params: [String: String] = [:]
        let pairs = query.split(separator: "&")

        for pair in pairs {
            let components = pair.split(separator: "=", maxSplits: 1)
            if components.count == 2 {
                let key = String(components[0])
                let rawValue = String(components[1])
                let value = rawValue.removingPercentEncoding ?? rawValue
                params[key] = value
            } else if components.count == 1 {
                params[String(components[0])] = ""
            }
        }

        return params
    }
}

// MARK: - Fragment & Query Expression Extraction

extension RFC6570TemplateExtractor {
    func extractQueryExpressions(
        template: String,
        url: String,
        variables: inout [String: String]
    ) -> (remainingTemplate: String, remainingURL: String)? {
        // Look for query expressions like {?var} or {&var}
        let queryPattern = #"\{[\?&][^}]+\}"#
        guard let regex = try? NSRegularExpression(pattern: queryPattern) else { return nil }

        let templateRange = NSRange(location: 0, length: template.utf16.count)
        let matches = regex.matches(in: template, range: templateRange)

        if matches.isEmpty {
            return nil
        }

        var remainingTemplate = template
        let urlParts = url.split(separator: "?", maxSplits: 1)
        let urlQuery = urlParts.count > 1 ? String(urlParts[1]) : ""

        // Parse URL query parameters
        let urlParams = parseQueryParameters(urlQuery)

        // Process each query expression
        for match in matches.reversed() { // Process in reverse to maintain string indices
            let matchRange = match.range
            let expressionString = String(template[Range(matchRange, in: template)!])

            // Remove the braces and get the content
            let content = String(expressionString.dropFirst().dropLast())
            let (_, variableSpecs) = parseExpression(content)

            // Extract variables from URL query parameters
            for variable in variableSpecs {
                if let value = urlParams[variable.name] {
                    variables[variable.name] = value
                }
            }

            // Remove the expression from the template
            let lower = Range(matchRange, in: remainingTemplate)!.lowerBound
            let upper = Range(matchRange, in: remainingTemplate)!.upperBound
            remainingTemplate = String(remainingTemplate[..<lower]) +
                String(remainingTemplate[upper...])
        }

        // Remove query part from URL since we've processed it
        let remainingURL = String(urlParts[0])

        return (remainingTemplate, remainingURL)
    }

    func extractFragmentExpression(
        template: String,
        url: String,
        variables: inout [String: String]
    ) -> (remainingTemplate: String, remainingURL: String)? {
        // Look for fragment expressions like {#var}
        let fragmentPattern = #"\{#[^}]+\}"#
        guard let regex = try? NSRegularExpression(pattern: fragmentPattern) else { return nil }

        let templateRange = NSRange(location: 0, length: template.utf16.count)
        guard let match = regex.firstMatch(in: template, range: templateRange) else { return nil }

        let matchRange = match.range
        let expressionString = String(template[Range(matchRange, in: template)!])

        // Remove the braces and get the content
        let content = String(expressionString.dropFirst().dropLast())
        let (_, variableSpecs) = parseExpression(content)

        // Extract fragment from URL
        let urlParts = url.split(separator: "#", maxSplits: 1)
        if urlParts.count > 1, let variable = variableSpecs.first {
            variables[variable.name] = String(urlParts[1])
        }

        // Remove the expression from template and fragment from URL
        let lower = Range(matchRange, in: template)!.lowerBound
        let upper = Range(matchRange, in: template)!.upperBound
        let remainingTemplate = String(template[..<lower]) + String(template[upper...])
        let remainingURL = String(urlParts[0])

        return (remainingTemplate, remainingURL)
    }

    func extractFromQuery(
        urlQuery: String?,
        templateQuery: String,
        variables: inout [String: String]
    ) -> Bool {
        guard let urlQuery = urlQuery else {
            // No query in URL, but template expects one - this might be okay for optional parameters
            return true
        }

        // Parse query parameters from both template and URL
        let templateParams = parseQueryParameters(templateQuery)
        let urlParams = parseQueryParameters(urlQuery)

        // Match template parameters
        for (key, templateValue) in templateParams {
            if templateValue.hasPrefix("{") && templateValue.hasSuffix("}") {
                // This is a variable
                let varName = String(templateValue.dropFirst().dropLast())
                if let actualValue = urlParams[key] {
                    variables[varName] = actualValue
                }
                // Missing parameters are okay for optional query params
            } else {
                // This is a literal value - must match exactly
                guard urlParams[key] == templateValue else {
                    return false
                }
            }
        }

        return true
    }

    func extractFromFragment(
        urlFragment: String,
        templateFragment: String,
        variables: inout [String: String]
    ) -> Bool {
        // Handle fragment expressions like {#var}
        if templateFragment.hasPrefix("{#") && templateFragment.hasSuffix("}") {
            let varName = String(templateFragment.dropFirst(2).dropLast())
            variables[varName] = urlFragment
            return true
        } else if templateFragment == urlFragment {
            return true
        }
        return false
    }
}
