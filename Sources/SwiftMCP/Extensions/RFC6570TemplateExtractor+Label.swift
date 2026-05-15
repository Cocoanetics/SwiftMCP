import Foundation

// MARK: - Label Extraction

extension RFC6570TemplateExtractor {
    func extractAllLabelVariables(
        variables: [VariableSpec],
        fromURL url: String,
        startingAt startIndex: String.Index
    ) -> (variables: [String: String], consumedLength: Int)? {

        // Label expansion starts with a dot
        guard startIndex < url.endIndex && url[startIndex] == "." else {
            return nil
        }

        var currentIndex = url.index(after: startIndex) // Skip the dot
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

        // Handle explode modifier (dot-separated → comma list)
        if variables.count == 1, let first = variables.first, case .explode = first.modifier {
            value = value.replacingOccurrences(of: ".", with: ",")
        }

        var result: [String: String] = [:]

        // Handle multiple variables (dot-separated)
        if variables.count > 1 && value.contains(".") {
            let values = value.split(separator: ".").map(String.init)
            for (index, variable) in variables.enumerated() where index < values.count {
                result[variable.name] = values[index]
            }
        } else if let firstVariable = variables.first {
            result[firstVariable.name] = value
        }

        return (result, consumedLength)
    }

    func extractLabelVariable(
        variables: [VariableSpec],
        fromURL url: String,
        startingAt startIndex: String.Index
    ) -> ExtractedVariable? {

        // Label expansion starts with a dot
        guard startIndex < url.endIndex && url[startIndex] == "." else {
            return nil
        }

        var currentIndex = url.index(after: startIndex) // Skip the dot
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

        // Handle explode modifier (dot-separated → comma list)
        if variables.count == 1, let first = variables.first, case .explode = first.modifier {
            value = value.replacingOccurrences(of: ".", with: ",")
        }

        // Handle multiple variables (dot-separated)
        if variables.count > 1 && value.contains(".") {
            let values = value.split(separator: ".").map(String.init)
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
}
