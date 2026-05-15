import Foundation

// MARK: - URI Template Constructor

/// RFC 6570 compliant URI template constructor
internal struct RFC6570TemplateConstructor {
    let template: String
    let parameters: JSONDictionary

    func construct() throws -> URL {
        var result = template

        // Find all expressions in the template
        let expressionPattern = #"\{[^}]+\}"#
        guard let regex = try? NSRegularExpression(pattern: expressionPattern) else {
            throw MCPResourceError.invalidTemplate(template: template)
        }

        let templateRange = NSRange(location: 0, length: template.utf16.count)
        let matches = regex.matches(in: template, range: templateRange)

        // Process matches in reverse order to maintain string indices
        for match in matches.reversed() {
            let matchRange = match.range
            guard let swiftRange = Range(matchRange, in: template) else { continue }

            let expressionString = String(template[swiftRange])
            let content = String(expressionString.dropFirst().dropLast()) // Remove { and }

            let replacement = try processExpression(content)
            result = result.replacingCharacters(in: swiftRange, with: replacement)
        }

        // Clean up empty query parameters
        result = cleanupEmptyQueryParameters(result)

        guard let url = URL(string: result) else {
            throw MCPResourceError.invalidTemplate(template: template)
        }

        return url
    }

    private func processExpression(_ expression: String) throws -> String {
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

        return try constructForOperator(operatorType, variables: variableSpecs)
    }

    private func parseVariableSpec(_ spec: String) -> VariableSpec? {
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

    private func constructForOperator(
        _ operatorType: ExpressionOperator,
        variables: [VariableSpec]
    ) throws -> String {
        switch operatorType {
        case .simple:
            return try constructSimple(variables: variables)
        case .reserved:
            return try constructReserved(variables: variables)
        case .fragment:
            return try constructFragment(variables: variables)
        case .label:
            return try constructLabel(variables: variables)
        case .pathSegment:
            return try constructPathSegment(variables: variables)
        case .pathStyle:
            return try constructPathStyle(variables: variables)
        case .query:
            return try constructQuery(variables: variables)
        case .queryContinuation:
            return try constructQueryContinuation(variables: variables)
        }
    }

    private func constructSimple(variables: [VariableSpec]) throws -> String {
        let values = variables.compactMap { variable -> String? in
            guard let value = getParameterValue(for: variable.name) else { return nil }
            return encodeValue(value, for: variable, allowReserved: false)
        }
        return values.joined(separator: ",")
    }

    private func constructReserved(variables: [VariableSpec]) throws -> String {
        let values = variables.compactMap { variable -> String? in
            guard let value = getParameterValue(for: variable.name) else { return nil }
            return encodeValue(value, for: variable, allowReserved: true)
        }
        return values.joined(separator: ",")
    }

    private func constructFragment(variables: [VariableSpec]) throws -> String {
        let values = variables.compactMap { variable -> String? in
            guard let value = getParameterValue(for: variable.name) else { return nil }
            return encodeValue(value, for: variable, allowReserved: true)
        }
        return values.isEmpty ? "" : "#" + values.joined(separator: ",")
    }

    private func constructLabel(variables: [VariableSpec]) throws -> String {
        let values = variables.compactMap { variable -> String? in
            guard let value = getParameterValue(for: variable.name) else { return nil }
            return encodeValue(value, for: variable, allowReserved: false)
        }
        return values.isEmpty ? "" : "." + values.joined(separator: ".")
    }

    private func constructPathSegment(variables: [VariableSpec]) throws -> String {
        let values = variables.compactMap { variable -> String? in
            guard let value = getParameterValue(for: variable.name) else { return nil }
            // For path segments, comma-separated values should become slash-separated
            if value.contains(",") {
                let segments = value.split(separator: ",").map { segment in
                    let trimmed = String(segment.trimmingCharacters(in: .whitespaces))
                    return encodeValue(trimmed, for: variable, allowReserved: false)
                }
                return segments.joined(separator: "/")
            } else {
                return encodeValue(value, for: variable, allowReserved: false)
            }
        }
        return values.isEmpty ? "" : "/" + values.joined(separator: "/")
    }

    private func constructPathStyle(variables: [VariableSpec]) throws -> String {
        let values = variables.compactMap { variable -> String? in
            guard let value = getParameterValue(for: variable.name) else { return nil }
            let encodedValue = encodeValue(value, for: variable, allowReserved: false)
            return ";\(variable.name)=\(encodedValue)"
        }
        return values.joined(separator: "")
    }

    private func constructQuery(variables: [VariableSpec]) throws -> String {
        let values = variables.compactMap { variable -> String? in
            guard let value = getParameterValue(for: variable.name), !value.isEmpty else { return nil }
            let encodedValue = encodeValue(value, for: variable, allowReserved: false)
            return "\(variable.name)=\(encodedValue)"
        }
        return values.isEmpty ? "" : "?" + values.joined(separator: "&")
    }

    private func constructQueryContinuation(variables: [VariableSpec]) throws -> String {
        let values = variables.compactMap { variable -> String? in
            guard let value = getParameterValue(for: variable.name), !value.isEmpty else { return nil }
            let encodedValue = encodeValue(value, for: variable, allowReserved: false)
            return "\(variable.name)=\(encodedValue)"
        }
        return values.isEmpty ? "" : "&" + values.joined(separator: "&")
    }

    private func getParameterValue(for name: String) -> String? {
        guard let value = parameters[name] else { return nil }
        switch value {
        case .null:
            return nil
        case .bool(let bool):
            return String(bool)
        case .integer(let integer):
            return String(integer)
        case .unsignedInteger(let integer):
            return String(integer)
        case .double(let double):
            return String(double)
        case .string(let string):
            return string
        case .array(let values):
            return values.compactMap { getParameterString(from: $0) }.joined(separator: ",")
        case .object:
            return nil
        }
    }

    private func getParameterString(from value: JSONValue) -> String? {
        switch value {
        case .null:
            return nil
        case .bool(let bool):
            return String(bool)
        case .integer(let integer):
            return String(integer)
        case .unsignedInteger(let integer):
            return String(integer)
        case .double(let double):
            return String(double)
        case .string(let string):
            return string
        case .array, .object:
            return nil
        }
    }

    private func cleanupEmptyQueryParameters(_ urlString: String) -> String {
        // Remove empty query parameters like "?param=" or "&param="
        var result = urlString

        // Pattern to match empty query parameters
        let emptyParamPattern = #"[?&][^=&]+=$"#
        if let regex = try? NSRegularExpression(pattern: emptyParamPattern) {
            let range = NSRange(location: 0, length: result.utf16.count)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "")
        }

        // Pattern to match empty query parameters in the middle
        let emptyParamMiddlePattern = #"[?&][^=&]+=&"#
        if let regex = try? NSRegularExpression(pattern: emptyParamMiddlePattern) {
            let range = NSRange(location: 0, length: result.utf16.count)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "&")
        }

        // Clean up trailing ? or & if all parameters were removed
        if result.hasSuffix("?") || result.hasSuffix("&") {
            result = String(result.dropLast())
        }

        return result
    }

    private func encodeValue(_ value: String, for variable: VariableSpec, allowReserved: Bool) -> String {
        var result = value

        // Apply prefix modifier if present
        if case .prefix(let length) = variable.modifier {
            result = String(result.prefix(length))
        }

        // URL encode the value
        let allowedCharacters: CharacterSet
        let reservedSet = CharacterSet(charactersIn: ":/?#[]@!$&'()*+,;=")
        if allowReserved {
            // For reserved expansion, allow more characters
            allowedCharacters = CharacterSet.urlQueryAllowed.union(reservedSet)
        } else {
            // For simple expansion, encode more strictly
            allowedCharacters = CharacterSet.urlQueryAllowed.subtracting(reservedSet)
        }

        return result.addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? result
    }
}
