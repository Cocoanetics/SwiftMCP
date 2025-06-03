//
//  Documentation.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 10.03.25.
//

import Foundation

struct Documentation {
/// The function's initial (multi‑line) description.
    let description: String
/// A dictionary mapping parameter names to their descriptions.
    let parameters: [String: String]
/// The returns section of the documentation, if present.
    let returns: String?


    init(from text: String)
	{
// First, split the input into individual lines.
        let lines = text.components(separatedBy: .newlines)

// Remove comment markers and extra whitespace from each line.
        var cleanedLines = [String]()
        var previousLineWasEmpty = false
        var inDocumentationBlock = false  // Track if we're inside a /** */ block

        for var line in lines {
// Trim whitespace first.
            line = line.trimmingCharacters(in: .whitespaces)

// Skip empty lines outside documentation blocks
            if line.isEmpty && !inDocumentationBlock {
                continue
            }

            var shouldProcessLine = false
            var isDocumentationLine = false

// Handle documentation block comments
            if line.hasPrefix("/**") {
                inDocumentationBlock = true
                line = line.replacingOccurrences(of: "/**", with: "")
                shouldProcessLine = true
                isDocumentationLine = true

// For single-line blocks, remove trailing */ immediately
                if line.hasSuffix("*/") {
                    line = String(line.dropLast(2)).trimmingCharacters(in: .whitespaces)
                }
            } else if line.hasSuffix("*/") {
// For multi-line blocks, remove trailing */ and end block
                    line = String(line.dropLast(2)).trimmingCharacters(in: .whitespaces)
                    shouldProcessLine = inDocumentationBlock
                    isDocumentationLine = inDocumentationBlock
                    inDocumentationBlock = false
                } else if line.hasPrefix("///") {
                        line = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
                        shouldProcessLine = true
                        isDocumentationLine = true
                    } else {
                        shouldProcessLine = inDocumentationBlock
                        isDocumentationLine = inDocumentationBlock
                    }

// Skip non-documentation lines
            if !shouldProcessLine {
                continue
            }

// Remove any leading asterisks used for formatting in documentation blocks
            if inDocumentationBlock && line.hasPrefix("*") {
                line = line.dropFirst().trimmingCharacters(in: .whitespaces)
            }

// Remove unprintable ASCII characters
            line = line.removingUnprintableCharacters

// For single-line documentation blocks with parameters, split into multiple lines
            if isDocumentationLine && line.contains(" - Parameter ") {
                let parts = line.components(separatedBy: " - Parameter ")
                if parts.count > 1 {
// First part is the description
                    cleanedLines.append(parts[0].trimmingCharacters(in: .whitespaces))

// Add each parameter as a separate line
                    for paramPart in parts.dropFirst() {
                        cleanedLines.append("- Parameter " + paramPart.trimmingCharacters(in: .whitespaces))
                    }
                    continue
                }
            }

// If the line is empty and the previous line wasn't empty, keep it to preserve paragraph breaks
            if line.isEmpty {
                if !previousLineWasEmpty {
                    cleanedLines.append(line)
                }
            } else {
                cleanedLines.append(line)
            }
            previousLineWasEmpty = line.isEmpty

// Now we can end the documentation block for single-line comments
            if line.hasSuffix("*/") {
                inDocumentationBlock = false
            }
        }

// We'll accumulate the initial description and any parameter descriptions.
        var initialDescriptionLines = [String]()
        var parameters = [String: String]()
        var returnsLines = [String]()

// Variables to hold state while processing a parameter that spans multiple lines.
        var currentParameterName: String? = nil
        var currentParameterLines = [String]()
        var inReturnsSection = false
        var inParametersSection = false
        var inOtherSection = false  // For any other dash-prefixed sections we don't specifically handle

// Helper to flush the current parameter's accumulated lines into our dictionary.
        func flushCurrentParameter() {
            if let paramName = currentParameterName {
// Join lines with a single space, but preserve existing spaces
                let fullDescription = currentParameterLines
					.map { $0.trimmingCharacters(in: .whitespaces) }
					.filter { !$0.isEmpty }
					.joined(separator: " ")
// Escape the description when storing it
                parameters[paramName] = fullDescription
            }
            currentParameterName = nil
            currentParameterLines = []
        }

// Helper to parse a parameter line with format "- name: description"
        func parseSimpleParameterLine(from line: String) -> (name: String, description: String)? {
// Check if the line starts with a dash followed by a name and colon
            if line.hasPrefix("-") {
                let trimmedLine = line.trimmingCharacters(in: .whitespaces)
                if let colonIndex = trimmedLine.firstIndex(of: ":") {
// Extract parameter name (after the dash and before the colon)
                    let nameStart = trimmedLine.index(trimmedLine.startIndex, offsetBy: 1) // Skip the dash
                    let name = trimmedLine[nameStart..<colonIndex].trimmingCharacters(in: .whitespaces)

// Extract description (after the colon)
                    let description = trimmedLine[trimmedLine.index(after: colonIndex)...].trimmingCharacters(in: .whitespaces)

                    return (name: name, description: description)
                }
            }
            return nil
        }

// Process each cleaned line.
        for lineIndex in 0..<cleanedLines.count {
            let line = cleanedLines[lineIndex]

// Check if this is a new section (starts with a dash)
            if line.hasPrefix("-") {
// This is a new section, which terminates any previous section

// Check for Parameters section
                if line.lowercased().hasPrefix("- parameters:") {
// Flush any parameter being processed
                    flushCurrentParameter()
                    inReturnsSection = false
                    inParametersSection = true
                    inOtherSection = false
                    continue
                }
				
				// Check for Returns section
				else if line.lowercased().hasPrefix("- returns:") {
// Flush any parameter being processed
                        flushCurrentParameter()
                        inParametersSection = false
                        inOtherSection = false

// Extract the returns description
                        let returnsDescription = line.dropFirst("- Returns:".count).trimmingCharacters(in: .whitespaces)
                        returnsLines = [returnsDescription]  // Start fresh with just this line
                        inReturnsSection = true
                        continue
                    }
				
				// Check for Parameter line (singular)
				else if let param = parseParameterLine(from: line) {
// Start of a new parameter: flush any previous parameter data.
                            flushCurrentParameter()
                            inReturnsSection = false
                            inParametersSection = false
                            inOtherSection = false
                            currentParameterName = param.name
                            currentParameterLines = [param.description]  // Start fresh with just this description
                            continue
                        }
				
				// Check for parameter in Parameters section
				else if inParametersSection {
// This could be a parameter under the Parameters section
                                if let param = parseSimpleParameterLine(from: line) {
// Flush any previous parameter
                                    flushCurrentParameter()

// Start a new parameter
                                    currentParameterName = param.name
                                    currentParameterLines = [param.description]
                                    continue
                                }
                            }
				
				// Any other dash-prefixed line is some other section we don't specifically handle
				else {
// Flush any parameter being processed
                                flushCurrentParameter()
                                inReturnsSection = false
                                inParametersSection = false
                                inOtherSection = true
                                continue
                            }
            }
			// Check for indented parameter in Parameters section (not starting with dash)
			else if inParametersSection && line.hasPrefix("  ") {
// This could be a continuation of the previous indented parameter
// or a new indented parameter line
                    let trimmedLine = line.trimmingCharacters(in: .whitespaces)

// Check if this is a new parameter line (starts with a dash)
                    if trimmedLine.hasPrefix("-") {
// This is a new indented parameter
                        if let param = parseSimpleParameterLine(from: trimmedLine) {
// Flush any previous parameter
                            flushCurrentParameter()

// Start a new parameter
                            currentParameterName = param.name
                            currentParameterLines = [param.description]
                        }
                    } else if currentParameterName != nil {
// This is a continuation of the previous indented parameter
                            currentParameterLines.append(trimmedLine)
                        }
                    continue
                }
			// Handle continuation lines for the current section
			else {
                    if currentParameterName != nil {
// If we are in the middle of a parameter, treat the line as a continuation.
// Only add non-empty lines and trim whitespace
                        let trimmedLine = line.trimmingCharacters(in: .whitespaces)
                        if !trimmedLine.isEmpty {
                            currentParameterLines.append(trimmedLine)
                        }
                    } else if inReturnsSection && !inOtherSection {
// If we're in the returns section, add to returns lines
                            returnsLines.append(line)
                        } else if !inParametersSection && !inOtherSection {
// If we're not in any special section, it belongs to the initial description.
                                initialDescriptionLines.append(line)
                            }
// If we're in the parameters section but not processing a specific parameter,
// or if we're in some other section we don't handle, we ignore the line
                }
        }

// Flush any parameter still being accumulated.
        flushCurrentParameter()

// Combine initial description lines into a single string, preserving paragraph breaks
        var initialDescription = ""
        previousLineWasEmpty = false  // Reuse the existing variable
        for line in initialDescriptionLines {
            if line.isEmpty {
                if !previousLineWasEmpty {
                    initialDescription += "\n\n"
                }
            } else {
                if !initialDescription.isEmpty && !previousLineWasEmpty {
                    initialDescription += " "
                }
                initialDescription += line
            }
            previousLineWasEmpty = line.isEmpty
        }
        initialDescription = initialDescription.trimmingCharacters(in: .whitespacesAndNewlines)

// Combine returns lines into a single string, preserving paragraph breaks
        var returnsDescription = ""
        previousLineWasEmpty = false  // Reuse the existing variable
        for line in returnsLines {
            if line.isEmpty {
                if !previousLineWasEmpty {
                    returnsDescription += "\n\n"
                }
            } else {
                if !returnsDescription.isEmpty && !previousLineWasEmpty {
                    returnsDescription += " "
                }
                returnsDescription += line
            }
            previousLineWasEmpty = line.isEmpty
        }
        returnsDescription = returnsDescription.trimmingCharacters(in: .whitespacesAndNewlines)

        self.description = initialDescription
        self.parameters = parameters
        self.returns = returnsDescription.isEmpty ? nil : returnsDescription
    }
}

/// Helper that checks if a line defines a parameter and, if so, extracts its name and description.
/// Expected format: "- Parameter <name>: <description>"
fileprivate func parseParameterLine(from line: String) -> (name: String, description: String)? {
// Check case-insensitively if the line starts with "- Parameter"
    if line.lowercased().hasPrefix("- parameter") {
// Remove the prefix.
        let startIndex = line.index(line.startIndex, offsetBy: "- Parameter".count)
        let remainder = line[startIndex...].trimmingCharacters(in: .whitespaces)

// Expect a colon separating the parameter name from its description.
        if let colonIndex = remainder.firstIndex(of: ":") {
            let name = remainder[..<colonIndex].trimmingCharacters(in: .whitespaces)
            let description = remainder[remainder.index(after: colonIndex)...].trimmingCharacters(in: .whitespaces)
            return (name: name, description: description)
        }
    }
    return nil
}
