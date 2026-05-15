import Foundation

// MARK: - Simple & Reserved Extraction

extension RFC6570TemplateExtractor {
    func extractAllSimpleVariables(
        variables: [VariableSpec],
        fromURL url: String,
        startingAt startIndex: String.Index
    ) -> (variables: [String: String], consumedLength: Int)? {

        let allowedChars = CharacterSet(charactersIn: "/?#").inverted
        var currentIndex = startIndex
        var value = ""

        while currentIndex < url.endIndex {
            let char = url[currentIndex]
            if allowedChars.contains(char.unicodeScalars.first!) {
                value.append(char)
                currentIndex = url.index(after: currentIndex)
            } else {
                break
            }
        }

        var result: [String: String] = [:]

        // Handle multiple variables (comma-separated)
        if variables.count > 1 && value.contains(",") {
            let values = value.split(separator: ",").map(String.init)
            for (index, variable) in variables.enumerated() where index < values.count {
                result[variable.name] = values[index]
            }
        } else if let firstVariable = variables.first {
            result[firstVariable.name] = value
        }

        // Always return a result, even for empty values
        return (result, value.count)
    }

    func extractAllReservedVariables(
        variables: [VariableSpec],
        fromURL url: String,
        startingAt startIndex: String.Index,
        followingLiteral: String
    ) -> (variables: [String: String], consumedLength: Int)? {

        // Allow "/"; stop only at query or fragment delimiters
        let allowedChars = CharacterSet(charactersIn: "#?").inverted
        var currentIndex = startIndex
        var value = ""

        while currentIndex < url.endIndex {
            let char = url[currentIndex]
            // Stop when the remaining URL matches the literal that follows the expression
            if !followingLiteral.isEmpty {
                let remaining = url[currentIndex...]
                if remaining.hasPrefix(followingLiteral) {
                    break
                }
            }
            if allowedChars.contains(char.unicodeScalars.first!) {
                value.append(char)
                currentIndex = url.index(after: currentIndex)
            } else {
                break
            }
        }

        // Handle explode modifier (dot-separated → comma list)
        if variables.count == 1, let first = variables.first, case .explode = first.modifier {
            value = value.replacingOccurrences(of: ".", with: ",")
        }

        // Keep track of how many characters we already consumed from the URL
        // *before* we potentially strip a leading slash.  We will still advance
        // the URL index by this amount, so downstream parsing stays aligned.
        let consumedLength = value.count

        // If the reserved expression appears directly after the host (e.g.
        // "http://example.com{+path}") the leading "/" acts only as a path
        // separator and should not be part of the variable's value.  Remove it
        // when there is exactly one variable in the expression.
        if variables.count == 1 && value.hasPrefix("/") {
            value.removeFirst()
        }

        var result: [String: String] = [:]

        // Handle multiple variables (comma-separated)
        if variables.count > 1 && value.contains(",") {
            let values = value.split(separator: ",").map(String.init)
            for (index, variable) in variables.enumerated() where index < values.count {
                result[variable.name] = values[index]
            }
        } else if let firstVariable = variables.first {
            result[firstVariable.name] = value
        }

        return (result, consumedLength)
    }

    func extractSimpleVariable(
        variables: [VariableSpec],
        fromURL url: String,
        startingAt startIndex: String.Index
    ) -> ExtractedVariable? {

        let allowedChars = CharacterSet(charactersIn: "/?#").inverted
        var currentIndex = startIndex
        var value = ""

        while currentIndex < url.endIndex {
            let char = url[currentIndex]
            if allowedChars.contains(char.unicodeScalars.first!) {
                value.append(char)
                currentIndex = url.index(after: currentIndex)
            } else {
                break
            }
        }

        // Handle multiple variables (comma-separated)
        if variables.count > 1 && value.contains(",") {
            let values = value.split(separator: ",").map(String.init)
            // For now, return the first variable with the first value
            // In a complete implementation, we'd need to return all variables
            if let firstVariable = variables.first, !values.isEmpty {
                return ExtractedVariable(
                    variableName: firstVariable.name,
                    value: values[0],
                    consumedLength: value.count
                )
            }
        }

        guard let firstVariable = variables.first else { return nil }
        return ExtractedVariable(
            variableName: firstVariable.name,
            value: value,
            consumedLength: value.count
        )
    }

    func extractReservedVariable(
        variables: [VariableSpec],
        fromURL url: String,
        startingAt startIndex: String.Index
    ) -> ExtractedVariable? {

        let allowedChars = CharacterSet(charactersIn: "#").inverted
        var currentIndex = startIndex
        var value = ""

        while currentIndex < url.endIndex {
            let char = url[currentIndex]
            if allowedChars.contains(char.unicodeScalars.first!) {
                value.append(char)
                currentIndex = url.index(after: currentIndex)
            } else {
                break
            }
        }

        // Remove leading slash if template did not include one
        var consumedLength = value.count
        if value.hasPrefix("/") {
            value.removeFirst()
            consumedLength -= 1
        }

        guard let firstVariable = variables.first else { return nil }
        return ExtractedVariable(
            variableName: firstVariable.name,
            value: value,
            consumedLength: consumedLength
        )
    }
}
