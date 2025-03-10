import Foundation

public func extractDocumentation(from leadingTrivia: String) -> (description: String?, parameters: [String: String]) {
    var sections: [String: String] = [:]
    var currentSection = "Description"
    
    // Check for single-line multi-line documentation (/** text */)
    let singleLineMultiLineRegex = try? NSRegularExpression(pattern: #"/\*\*\s*(.*?)\s*\*/"#, options: .dotMatchesLineSeparators)
    if let match = singleLineMultiLineRegex?.firstMatch(in: leadingTrivia, options: [], range: NSRange(location: 0, length: leadingTrivia.utf16.count)) {
        if let range = Range(match.range(at: 1), in: leadingTrivia) {
            let description = String(leadingTrivia[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            return (description, [:])
        }
    }
    
    // Process each line of the leading trivia
    let lines = leadingTrivia.split(separator: "\n", omittingEmptySubsequences: false)
    
    for line in lines {
        var cleanedLine = String(line).trimmingCharacters(in: .whitespaces)
        
        // Skip empty lines and non-documentation comments
        if cleanedLine.isEmpty || (cleanedLine.starts(with: "//") && !cleanedLine.starts(with: "///")) {
            continue
        }
        
        // Remove documentation comment markers
        if cleanedLine.starts(with: "///") {
            cleanedLine = String(cleanedLine.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        } else if cleanedLine.starts(with: "/**") || cleanedLine.starts(with: "*") || cleanedLine.starts(with: "*/") {
            // Skip the opening/closing of multi-line comments
            if cleanedLine == "/**" || cleanedLine == "*/" {
                continue
            }
            
            // Remove the leading * from multi-line comment lines
            if cleanedLine.starts(with: "*") {
                cleanedLine = String(cleanedLine.dropFirst(1)).trimmingCharacters(in: .whitespaces)
            }
        }
        
        // Check for parameter documentation
        if cleanedLine.starts(with: "- Parameter ") {
            let parameterLine = String(cleanedLine.dropFirst("- Parameter ".count))
            let components = parameterLine.split(separator: ":", maxSplits: 1)
            
            if components.count == 2 {
                let paramName = String(components[0]).trimmingCharacters(in: .whitespaces)
                let paramDescription = String(components[1]).trimmingCharacters(in: .whitespaces)
                
                currentSection = "Parameter \(paramName)"
                sections[currentSection] = paramDescription
            }
        } else if cleanedLine.starts(with: "-") {
            // Other markers like "- Returns:" start a new section but we don't track them
            currentSection = ""
        } else if !currentSection.isEmpty {
            // Append to the current section
            if let existing = sections[currentSection] {
                sections[currentSection] = existing + " " + cleanedLine
            } else {
                sections[currentSection] = cleanedLine
            }
        }
    }
    
    // Extract parameter descriptions
    var parameterDescriptions: [String: String] = [:]
    for (key, value) in sections {
        if key.starts(with: "Parameter ") {
            let paramName = String(key.dropFirst("Parameter ".count))
            parameterDescriptions[paramName] = value
        }
    }
    
    // Return the description and parameter descriptions
    let description = sections["Description"]?.isEmpty == false ? sections["Description"] : nil
    
    return (description, parameterDescriptions)
} 