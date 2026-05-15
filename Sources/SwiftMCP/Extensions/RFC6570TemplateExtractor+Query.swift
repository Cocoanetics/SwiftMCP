import Foundation

// MARK: - Query Variable Extraction

extension RFC6570TemplateExtractor {
    func extractQueryVariable(
        variables: [VariableSpec],
        fromURL url: String,
        startingAt startIndex: String.Index
    ) -> ExtractedVariable? {

        // Query parameters are in format ?name=value or &name=value
        var currentIndex = startIndex
        var consumedLength = 0

        // Skip ? or &
        if currentIndex < url.endIndex
            && (url[currentIndex] == "?" || url[currentIndex] == "&") {
            currentIndex = url.index(after: currentIndex)
            consumedLength += 1
        }

        // Find parameter name
        var paramName = ""
        while currentIndex < url.endIndex
            && url[currentIndex] != "="
            && url[currentIndex] != "&" {
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

            // Extract value until & or end
            while currentIndex < url.endIndex
                && url[currentIndex] != "&"
                && url[currentIndex] != "#" {
                value.append(url[currentIndex])
                currentIndex = url.index(after: currentIndex)
                consumedLength += 1
            }
        }

        // URL decode the value
        let decodedValue = value.removingPercentEncoding ?? value

        return ExtractedVariable(
            variableName: paramName,
            value: decodedValue,
            consumedLength: consumedLength
        )
    }
}
