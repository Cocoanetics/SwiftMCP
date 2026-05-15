import Foundation

// MARK: - Path Segment & Path Style Extraction

extension RFC6570TemplateExtractor {
    func extractAllPathSegmentVariables(
        variables: [VariableSpec],
        fromURL url: String,
        startingAt startIndex: String.Index
    ) -> (variables: [String: String], consumedLength: Int)? {

        // Path segment expansion starts with a slash
        guard startIndex < url.endIndex && url[startIndex] == "/" else {
            return nil
        }

        var currentIndex = url.index(after: startIndex) // Skip the initial slash
        var consumedLength = 1

        // Special-case: single variable with explode modifier → gather all remaining segments
        if variables.count == 1,
           let first = variables.first,
           case .explode = first.modifier {
            let (segValue, length) = collectExplodedPathSegments(
                url: url,
                startingAt: currentIndex,
                initialConsumed: consumedLength
            )
            var result: [String: String] = [:]
            result[first.name] = segValue.trimmingCharacters(in: CharacterSet(charactersIn: ","))
            return (result, length)
        }

        var result: [String: String] = [:]

        // For multiple variables, each gets its own path segment
        for (index, variable) in variables.enumerated() {
            let segmentValue = consumePathSegment(
                url: url,
                currentIndex: &currentIndex,
                consumedLength: &consumedLength,
                isLast: index == variables.count - 1
            )
            result[variable.name] = segmentValue

            // If we've reached the end of the URL and there are more variables, stop
            if currentIndex >= url.endIndex && index < variables.count - 1 {
                break
            }
        }

        return (result, consumedLength)
    }

    /// Walks the URL until the next path/query/fragment boundary, returning the
    /// segment value and advancing `currentIndex`/`consumedLength` in place.
    /// When this is not the final variable, the trailing slash is consumed so
    /// the next iteration starts cleanly.
    private func consumePathSegment(
        url: String,
        currentIndex: inout String.Index,
        consumedLength: inout Int,
        isLast: Bool
    ) -> String {
        var segmentValue = ""

        while currentIndex < url.endIndex {
            let char = url[currentIndex]
            if char == "/" {
                if !isLast {
                    // Not the last variable, consume the slash and continue
                    currentIndex = url.index(after: currentIndex)
                    consumedLength += 1
                }
                break
            } else if char == "?" || char == "#" {
                // Found query or fragment, stop
                break
            } else {
                segmentValue.append(char)
                currentIndex = url.index(after: currentIndex)
                consumedLength += 1
            }
        }

        return segmentValue
    }

    /// Gathers remaining path segments as a comma-joined string for the
    /// single-variable explode case (`{/var*}`).
    private func collectExplodedPathSegments(
        url: String,
        startingAt startIndex: String.Index,
        initialConsumed: Int
    ) -> (value: String, consumedLength: Int) {
        var currentIndex = startIndex
        var consumedLength = initialConsumed
        var segValue = ""

        while currentIndex < url.endIndex {
            let character = url[currentIndex]
            if character == "?" || character == "#" {
                break
            }
            if character == "/" {
                segValue.append(",")
                currentIndex = url.index(after: currentIndex)
                consumedLength += 1
                continue
            }
            segValue.append(character)
            currentIndex = url.index(after: currentIndex)
            consumedLength += 1
        }

        return (segValue, consumedLength)
    }

    func extractAllPathStyleVariables(
        variables: [VariableSpec],
        fromURL url: String,
        startingAt startIndex: String.Index
    ) -> (variables: [String: String], consumedLength: Int)? {

        var currentIndex = startIndex
        var consumedLength = 0
        var result: [String: String] = [:]

        // Extract all path-style parameters like ;id=123;name=john
        for variable in variables {
            // Look for ;variableName=value
            guard currentIndex < url.endIndex && url[currentIndex] == ";" else {
                // If we can't find the expected parameter, this might be optional
                continue
            }

            consumePathStyleParameter(
                url: url,
                currentIndex: &currentIndex,
                consumedLength: &consumedLength,
                variable: variable,
                result: &result
            )
        }

        return result.isEmpty ? nil : (result, consumedLength)
    }

    /// Consumes a single `;name=value` segment from the URL and stores it in
    /// `result` if the name matches the expected variable.
    private func consumePathStyleParameter(
        url: String,
        currentIndex: inout String.Index,
        consumedLength: inout Int,
        variable: VariableSpec,
        result: inout [String: String]
    ) {
        var paramIndex = url.index(after: currentIndex) // Skip the ;
        consumedLength += 1

        // Extract parameter name
        var paramName = ""
        while paramIndex < url.endIndex
            && url[paramIndex] != "="
            && url[paramIndex] != ";" {
            paramName.append(url[paramIndex])
            paramIndex = url.index(after: paramIndex)
            consumedLength += 1
        }

        if paramName == variable.name {
            let value = readPathStyleValue(
                url: url,
                paramIndex: &paramIndex,
                consumedLength: &consumedLength
            )
            result[variable.name] = value
            currentIndex = paramIndex
        } else {
            // This parameter doesn't match, backtrack
            currentIndex = url.index(after: currentIndex)
            consumedLength = 1

            // Skip to the next semicolon or end
            while currentIndex < url.endIndex
                && url[currentIndex] != ";"
                && url[currentIndex] != "?"
                && url[currentIndex] != "#" {
                currentIndex = url.index(after: currentIndex)
                consumedLength += 1
            }
        }
    }

    /// Reads the value portion of a `;name=value` path-style segment.
    private func readPathStyleValue(
        url: String,
        paramIndex: inout String.Index,
        consumedLength: inout Int
    ) -> String {
        var value = ""
        if paramIndex < url.endIndex && url[paramIndex] == "=" {
            paramIndex = url.index(after: paramIndex) // Skip the =
            consumedLength += 1

            while paramIndex < url.endIndex
                && url[paramIndex] != ";"
                && url[paramIndex] != "?"
                && url[paramIndex] != "#" {
                value.append(url[paramIndex])
                paramIndex = url.index(after: paramIndex)
                consumedLength += 1
            }
        }
        return value
    }

    func extractPathSegmentVariable(
        variables: [VariableSpec],
        fromURL url: String,
        startingAt startIndex: String.Index
    ) -> ExtractedVariable? {

        // Path segment expansion starts with a slash
        guard startIndex < url.endIndex && url[startIndex] == "/" else {
            return nil
        }

        var currentIndex = url.index(after: startIndex) // Skip the slash
        var consumedLength = 1
        var value = ""

        let allowedChars = CharacterSet(charactersIn: "/?#").inverted

        while currentIndex < url.endIndex {
            let char = url[currentIndex]
            if allowedChars.contains(char.unicodeScalars.first!) {
                value.append(char)
                currentIndex = url.index(after: currentIndex)
                consumedLength += 1
            } else {
                break
            }
        }

        // Handle multiple variables (slash-separated)
        if variables.count > 1 && value.contains("/") {
            let values = value.split(separator: "/").map(String.init)
            if let firstVariable = variables.first, !values.isEmpty {
                return ExtractedVariable(
                    variableName: firstVariable.name,
                    value: values[0],
                    consumedLength: consumedLength
                )
            }
        }

        guard let firstVariable = variables.first else { return nil }
        return ExtractedVariable(
            variableName: firstVariable.name,
            value: value,
            consumedLength: consumedLength
        )
    }

    func extractPathStyleVariable(
        variables: [VariableSpec],
        fromURL url: String,
        startingAt startIndex: String.Index
    ) -> ExtractedVariable? {

        // Path style parameters start with ; and are in format ;name=value
        guard startIndex < url.endIndex && url[startIndex] == ";" else {
            return nil
        }

        var currentIndex = url.index(after: startIndex) // Skip the ;
        var consumedLength = 1

        // Find the parameter name
        var paramName = ""
        while currentIndex < url.endIndex
            && url[currentIndex] != "="
            && url[currentIndex] != ";" {
            paramName.append(url[currentIndex])
            currentIndex = url.index(after: currentIndex)
            consumedLength += 1
        }

        // Check if this matches one of our variables
        guard variables.contains(where: { $0.name == paramName }) else {
            return nil
        }

        var value = ""
        if currentIndex < url.endIndex && url[currentIndex] == "=" {
            currentIndex = url.index(after: currentIndex) // Skip the =
            consumedLength += 1

            // Extract value until ; or end
            while currentIndex < url.endIndex
                && url[currentIndex] != ";"
                && url[currentIndex] != "?"
                && url[currentIndex] != "#" {
                value.append(url[currentIndex])
                currentIndex = url.index(after: currentIndex)
                consumedLength += 1
            }
        }

        return ExtractedVariable(
            variableName: paramName,
            value: value,
            consumedLength: consumedLength
        )
    }
}
