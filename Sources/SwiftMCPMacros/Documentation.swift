//
//  Documentation.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 10.03.25.
//


struct Documentation {
	/// The function’s initial (multi‑line) description.
	let description: String
	/// A dictionary mapping parameter names to their descriptions.
	let parameters: [String: String]
	
	
	init(from text: String)
	{
		// First, split the input into individual lines.
		let lines = text.components(separatedBy: .newlines)
		
		// Remove comment markers and extra whitespace from each line.
		var cleanedLines = [String]()
		for var line in lines {
			// Trim whitespace first.
			line = line.trimmingCharacters(in: .whitespaces)
			
			// Remove leading triple-slash markers.
			if line.hasPrefix("///") {
				line = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
			}
			
			// Remove block comment start/end markers.
			if line.hasPrefix("/**") {
				line = line.replacingOccurrences(of: "/**", with: "")
			}
			if line.hasPrefix("/*") {
				line = line.replacingOccurrences(of: "/*", with: "")
			}
			if line.hasSuffix("*/") {
				line = line.replacingOccurrences(of: "*/", with: "")
			}
			
			// Remove any leading asterisks used for formatting.
			if line.hasPrefix("*") {
				line = line.dropFirst().trimmingCharacters(in: .whitespaces)
			}
			
			// If the line isn’t empty after cleaning, keep it.
			if !line.isEmpty {
				cleanedLines.append(line)
			}
		}
		
		// We'll accumulate the initial description and any parameter descriptions.
		var initialDescriptionLines = [String]()
		var parameters = [String: String]()
		
		// Variables to hold state while processing a parameter that spans multiple lines.
		var currentParameterName: String? = nil
		var currentParameterLines = [String]()
		
		// Helper to flush the current parameter’s accumulated lines into our dictionary.
		func flushCurrentParameter() {
			if let paramName = currentParameterName {
				let fullDescription = currentParameterLines.joined(separator: " ").trimmingCharacters(in: .whitespaces)
				parameters[paramName] = fullDescription
			}
			currentParameterName = nil
			currentParameterLines = []
		}
		
		// Process each cleaned line.
		for line in cleanedLines {
			if let param = parseParameterLine(from: line) {
				// Start of a new parameter: flush any previous parameter data.
				flushCurrentParameter()
				currentParameterName = param.name
				currentParameterLines.append(param.description)
			} else {
				// If we are in the middle of a parameter, treat the line as a continuation.
				if currentParameterName != nil {
					currentParameterLines.append(line)
				} else {
					// Otherwise, it belongs to the initial description.
					initialDescriptionLines.append(line)
				}
			}
		}
		// Flush any parameter still being accumulated.
		flushCurrentParameter()
		
		// Combine initial description lines into a single string.
		let initialDescription = initialDescriptionLines.joined(separator: " ").trimmingCharacters(in: .whitespaces)
		
		self.description = initialDescription
		self.parameters = parameters
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
