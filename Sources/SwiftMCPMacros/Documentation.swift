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

    init(from text: String) {
        let cleanedLines = Self.cleanDocumentationLines(from: text)
        let parsed = Self.parseSections(from: cleanedLines)

        self.description = Self.combineLines(parsed.descriptionLines)
        self.parameters = parsed.parameters
        let returnsDescription = Self.combineLines(parsed.returnsLines)
        self.returns = returnsDescription.isEmpty ? nil : returnsDescription
    }

    // MARK: - Line cleaning

    /// Removes comment markers and extra whitespace from each line, leaving
    /// only the textual content of the documentation.
    private static func cleanDocumentationLines(from text: String) -> [String] {
        let lines = text.components(separatedBy: .newlines)
        var cleanedLines = [String]()
        var previousLineWasEmpty = false
        var inDocumentationBlock = false

        for var line in lines {
            line = line.trimmingCharacters(in: .whitespaces)

            if line.isEmpty && !inDocumentationBlock {
                continue
            }

            let cleanResult = cleanLine(line, inDocumentationBlock: &inDocumentationBlock)
            guard cleanResult.shouldProcess else { continue }
            line = cleanResult.line

            if inDocumentationBlock && line.hasPrefix("*") {
                line = line.dropFirst().trimmingCharacters(in: .whitespaces)
            }

            line = line.removingUnprintableCharacters

            // For single-line documentation blocks with parameters, split into multiple lines
            if cleanResult.isDocumentationLine && line.contains(" - Parameter ") {
                if appendSplitParameters(line: line, into: &cleanedLines) {
                    continue
                }
            }

            if line.isEmpty {
                if !previousLineWasEmpty {
                    cleanedLines.append(line)
                }
            } else {
                cleanedLines.append(line)
            }
            previousLineWasEmpty = line.isEmpty

            if line.hasSuffix("*/") {
                inDocumentationBlock = false
            }
        }

        return cleanedLines
    }

    private struct CleanLineResult {
        var line: String
        var shouldProcess: Bool
        var isDocumentationLine: Bool
    }

    /// Strips comment markers (`///`, `/**`, `*/`) from a single line, updating
    /// the multi-line block flag as appropriate.
    private static func cleanLine(_ raw: String, inDocumentationBlock: inout Bool) -> CleanLineResult {
        var line = raw
        if line.hasPrefix("/**") {
            inDocumentationBlock = true
            line = line.replacingOccurrences(of: "/**", with: "")
            if line.hasSuffix("*/") {
                line = String(line.dropLast(2)).trimmingCharacters(in: .whitespaces)
            }
            return CleanLineResult(line: line, shouldProcess: true, isDocumentationLine: true)
        }
        if line.hasSuffix("*/") {
            line = String(line.dropLast(2)).trimmingCharacters(in: .whitespaces)
            let wasInBlock = inDocumentationBlock
            inDocumentationBlock = false
            return CleanLineResult(line: line, shouldProcess: wasInBlock, isDocumentationLine: wasInBlock)
        }
        if line.hasPrefix("///") {
            line = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
            return CleanLineResult(line: line, shouldProcess: true, isDocumentationLine: true)
        }
        return CleanLineResult(
            line: line,
            shouldProcess: inDocumentationBlock,
            isDocumentationLine: inDocumentationBlock
        )
    }

    /// Splits a single-line block that contains multiple inline `- Parameter`
    /// entries into separate lines. Returns true if a split occurred and the
    /// caller should skip default appending.
    private static func appendSplitParameters(line: String, into cleanedLines: inout [String]) -> Bool {
        let parts = line.components(separatedBy: " - Parameter ")
        guard parts.count > 1 else { return false }
        cleanedLines.append(parts[0].trimmingCharacters(in: .whitespaces))
        for paramPart in parts.dropFirst() {
            cleanedLines.append("- Parameter " + paramPart.trimmingCharacters(in: .whitespaces))
        }
        return true
    }

    // MARK: - Section parsing

    private struct ParsedDocumentation {
        var descriptionLines: [String] = []
        var parameters: [String: String] = [:]
        var returnsLines: [String] = []
    }

    private final class ParsingState {
        var currentParameterName: String?
        var currentParameterLines: [String] = []
        var inReturnsSection = false
        var inParametersSection = false
        var inOtherSection = false
    }

    /// Walks the cleaned lines and populates the description, parameters, and
    /// returns sections.
    private static func parseSections(from cleanedLines: [String]) -> ParsedDocumentation {
        var result = ParsedDocumentation()
        let state = ParsingState()

        for line in cleanedLines {
            if line.hasPrefix("-") {
                handleDashLine(line, state: state, result: &result)
            } else if state.inParametersSection && line.hasPrefix("  ") {
                handleIndentedParameterLine(line, state: state, result: &result)
            } else {
                handleContinuationLine(line, state: state, result: &result)
            }
        }

        flushCurrentParameter(state: state, result: &result)
        return result
    }

    private static func handleDashLine(
        _ line: String,
        state: ParsingState,
        result: inout ParsedDocumentation
    ) {
        let lowered = line.lowercased()

        if lowered.hasPrefix("- parameters:") {
            flushCurrentParameter(state: state, result: &result)
            state.inReturnsSection = false
            state.inParametersSection = true
            state.inOtherSection = false
            return
        }

        if lowered.hasPrefix("- returns:") {
            flushCurrentParameter(state: state, result: &result)
            state.inParametersSection = false
            state.inOtherSection = false
            let returnsDescription = line.dropFirst("- Returns:".count).trimmingCharacters(in: .whitespaces)
            result.returnsLines = [returnsDescription]
            state.inReturnsSection = true
            return
        }

        if let param = parseParameterLine(from: line) {
            flushCurrentParameter(state: state, result: &result)
            state.inReturnsSection = false
            state.inParametersSection = false
            state.inOtherSection = false
            state.currentParameterName = param.name
            state.currentParameterLines = [param.description]
            return
        }

        if state.inParametersSection, let param = parseSimpleParameterLine(from: line) {
            flushCurrentParameter(state: state, result: &result)
            state.currentParameterName = param.name
            state.currentParameterLines = [param.description]
            return
        }

        // Any other dash-prefixed line is a section we don't handle.
        flushCurrentParameter(state: state, result: &result)
        state.inReturnsSection = false
        state.inParametersSection = false
        state.inOtherSection = true
    }

    private static func handleIndentedParameterLine(
        _ line: String,
        state: ParsingState,
        result: inout ParsedDocumentation
    ) {
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)
        if trimmedLine.hasPrefix("-") {
            if let param = parseSimpleParameterLine(from: trimmedLine) {
                flushCurrentParameter(state: state, result: &result)
                state.currentParameterName = param.name
                state.currentParameterLines = [param.description]
            }
        } else if state.currentParameterName != nil {
            state.currentParameterLines.append(trimmedLine)
        }
    }

    private static func handleContinuationLine(
        _ line: String,
        state: ParsingState,
        result: inout ParsedDocumentation
    ) {
        if state.currentParameterName != nil {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if !trimmedLine.isEmpty {
                state.currentParameterLines.append(trimmedLine)
            }
        } else if state.inReturnsSection && !state.inOtherSection {
            result.returnsLines.append(line)
        } else if !state.inParametersSection && !state.inOtherSection {
            result.descriptionLines.append(line)
        }
    }

    private static func flushCurrentParameter(
        state: ParsingState,
        result: inout ParsedDocumentation
    ) {
        if let paramName = state.currentParameterName {
            let fullDescription = state.currentParameterLines
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            result.parameters[paramName] = fullDescription
        }
        state.currentParameterName = nil
        state.currentParameterLines = []
    }

    private static func parseSimpleParameterLine(from line: String) -> (name: String, description: String)? {
        guard line.hasPrefix("-") else { return nil }
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)
        guard let colonIndex = trimmedLine.firstIndex(of: ":") else { return nil }
        let nameStart = trimmedLine.index(trimmedLine.startIndex, offsetBy: 1)
        let name = trimmedLine[nameStart..<colonIndex].trimmingCharacters(in: .whitespaces)
        let afterColon = trimmedLine[trimmedLine.index(after: colonIndex)...]
        let description = afterColon.trimmingCharacters(in: .whitespaces)
        return (name: name, description: description)
    }

    // MARK: - Combining

    /// Joins a list of lines into a single string, collapsing consecutive
    /// empty lines into paragraph breaks.
    private static func combineLines(_ lines: [String]) -> String {
        var combined = ""
        var previousLineWasEmpty = false
        for line in lines {
            if line.isEmpty {
                if !previousLineWasEmpty {
                    combined += "\n\n"
                }
            } else {
                if !combined.isEmpty && !previousLineWasEmpty {
                    combined += " "
                }
                combined += line
            }
            previousLineWasEmpty = line.isEmpty
        }
        return combined.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Helper that checks if a line defines a parameter and, if so, extracts its name and description.
/// Expected format: "- Parameter <name>: <description>"
private func parseParameterLine(from line: String) -> (name: String, description: String)? {
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
