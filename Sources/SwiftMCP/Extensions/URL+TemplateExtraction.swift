import Foundation

extension URL {
	/// Extracts named variables from a URL based on an RFC 6570 URI template
	/// - Parameter template: RFC 6570 compliant URI template
	/// - Returns: Dictionary of variable names and their values, or nil if URL doesn't match template pattern
	public func extractTemplateVariables(from template: String) -> [String: String]? {
		let extractor = RFC6570TemplateExtractor(template: template, url: self)
		return extractor.extract()
	}
	
	/// Returns true if the URL matches the given RFC 6570 template
	public func matches(template: String) -> Bool {
		return self.extractTemplateVariables(from: template) != nil
	}
}

/// RFC 6570 compliant URI template extractor
private struct RFC6570TemplateExtractor {
	let template: String
	let url: URL
	
	init(template: String, url: URL) {
		self.template = template
		self.url = url
	}
	
	func extract() -> [String: String]? {
		// Split URL and template into components for easier matching
		let urlString = url.absoluteString
		
		// Handle different parts of the URL separately
		return extractFromComponents(urlString: urlString, template: template)
	}
	
	private func extractFromComponents(urlString: String, template: String) -> [String: String]? {
		var variables: [String: String] = [:]
		
		// First, handle query and fragment expressions that are part of the template structure
		var processedTemplate = template
		var processedURL = urlString
		
		// Handle fragment expressions like {#var}
		if let fragmentMatch = extractFragmentExpression(template: template, url: urlString, variables: &variables) {
			processedTemplate = fragmentMatch.remainingTemplate
			processedURL = fragmentMatch.remainingURL
		}
		
		// Handle query expressions like {?var} and {&var}
		if let queryMatch = extractQueryExpressions(template: processedTemplate, url: processedURL, variables: &variables) {
			processedTemplate = queryMatch.remainingTemplate
			processedURL = queryMatch.remainingURL
		}
		
		// Now handle the base URL (everything before query/fragment)
		let templateParts = processedTemplate.split(separator: "?", maxSplits: 1)
		let urlParts = processedURL.split(separator: "?", maxSplits: 1)
		
		let templateBase = String(templateParts[0])
		let urlBase = String(urlParts[0])
		
		// Extract from base URL (path part)
		guard extractFromBase(urlBase: urlBase, templateBase: templateBase, variables: &variables) else {
			return nil
		}
		
		// Handle any remaining literal query parameters
		if templateParts.count > 1 && urlParts.count > 1 {
			let templateQuery = String(templateParts[1])
			let urlQuery = String(urlParts[1])
			guard extractFromQuery(urlQuery: urlQuery, templateQuery: templateQuery, variables: &variables) else {
				return nil
			}
		}
		
		return variables
	}
	
	private func extractFromBase(urlBase: String, templateBase: String, variables: inout [String: String]) -> Bool {
		// Handle different expression types in the base URL
		var templateIndex = templateBase.startIndex
		var urlIndex = urlBase.startIndex
		
		while templateIndex < templateBase.endIndex {
			if templateBase[templateIndex] == "{" {
				// Find the closing brace
				guard let closingBrace = templateBase[templateIndex...].firstIndex(of: "}") else {
					return false
				}
				
				let expressionContent = String(templateBase[templateBase.index(after: templateIndex)..<closingBrace])
				
				// Determine the literal substring that follows this expression, until next expression or end
				let followingLiteral: String = {
					let nextIndex = templateBase.index(after: closingBrace)
					guard nextIndex < templateBase.endIndex else { return "" }
					let rest = templateBase[nextIndex...]
					if let nextBrace = rest.firstIndex(of: "{") {
						return String(rest[..<nextBrace])
					} else {
						return String(rest)
					}
				}()
				
				// Parse the expression and extract values for all variables
				guard let extractedVariables = extractAllVariablesFromExpression(
					expression: expressionContent,
					fromURL: urlBase,
					startingAt: urlIndex,
					followingLiteral: followingLiteral
				) else {
					return false
				}
				
				// Add all extracted variables
				for (name, value) in extractedVariables.variables {
					variables[name] = value
				}
				
				// Move indices
				templateIndex = templateBase.index(after: closingBrace)
				urlIndex = urlBase.index(urlIndex, offsetBy: extractedVariables.consumedLength)
				
			} else {
				// Literal character - must match exactly
				guard urlIndex < urlBase.endIndex else { return false }
				if templateBase[templateIndex] != urlBase[urlIndex] {
					return false
				}
				templateIndex = templateBase.index(after: templateIndex)
				urlIndex = urlBase.index(after: urlIndex)
			}
		}
		
		// Both should be at the end for a valid match
		if templateIndex == templateBase.endIndex {
			// Template is fully processed - URL should also be fully processed
			return urlIndex == urlBase.endIndex
		}
		
		// If there are remaining template characters, they should only be literal characters that match the URL
		while templateIndex < templateBase.endIndex && urlIndex < urlBase.endIndex {
			if templateBase[templateIndex] != urlBase[urlIndex] {
				return false
			}
			templateIndex = templateBase.index(after: templateIndex)
			urlIndex = urlBase.index(after: urlIndex)
		}
		
		return templateIndex == templateBase.endIndex
	}
	
	private func extractAllVariablesFromExpression(
		expression: String,
		fromURL url: String,
		startingAt startIndex: String.Index,
		followingLiteral: String
	) -> (variables: [String: String], consumedLength: Int)? {
		
		// Parse the expression
		let (operatorType, variableSpecs) = parseExpression(expression)
		
		guard !variableSpecs.isEmpty else { return nil }
		
		switch operatorType {
		case .simple:
			return extractAllSimpleVariables(variables: variableSpecs, fromURL: url, startingAt: startIndex)
		case .reserved:
			return extractAllReservedVariables(variables: variableSpecs, fromURL: url, startingAt: startIndex, followingLiteral: followingLiteral)
		case .label:
			return extractAllLabelVariables(variables: variableSpecs, fromURL: url, startingAt: startIndex)
		case .pathSegment:
			return extractAllPathSegmentVariables(variables: variableSpecs, fromURL: url, startingAt: startIndex)
		case .pathStyle:
			return extractAllPathStyleVariables(variables: variableSpecs, fromURL: url, startingAt: startIndex)
		case .query, .queryContinuation:
			if let result = extractQueryVariable(variables: variableSpecs, fromURL: url, startingAt: startIndex) {
				return ([result.variableName: result.value], result.consumedLength)
			}
			return nil
		case .fragment:
			// Fragments are handled separately in extractFragmentExpression
			return nil
		}
	}
	
	private func extractAllSimpleVariables(
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
			for (index, variable) in variables.enumerated() {
				if index < values.count {
					result[variable.name] = values[index]
				}
			}
		} else if let firstVariable = variables.first {
			result[firstVariable.name] = value
		}
		
		// Always return a result, even for empty values
		return (result, value.count)
	}
	
	private func extractAllReservedVariables(
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
		// separator and should not be part of the variable’s value.  Remove it
		// when there is exactly one variable in the expression.
		if variables.count == 1 && value.hasPrefix("/") {
			value.removeFirst()
		}

		var result: [String: String] = [:]
		
		// Handle multiple variables (comma-separated)
		if variables.count > 1 && value.contains(",") {
			let values = value.split(separator: ",").map(String.init)
			for (index, variable) in variables.enumerated() {
				if index < values.count {
					result[variable.name] = values[index]
				}
			}
		} else if let firstVariable = variables.first {
			result[firstVariable.name] = value
		}
		
		return (result, consumedLength)
	}
	
	private func extractAllLabelVariables(
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
			for (index, variable) in variables.enumerated() {
				if index < values.count {
					result[variable.name] = values[index]
				}
			}
		} else if let firstVariable = variables.first {
			result[firstVariable.name] = value
		}
		
		return (result, consumedLength)
	}
	
	private func extractAllPathSegmentVariables(
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
		var result: [String: String] = [:]
		
		// Special-case: single variable with explode modifier → gather all remaining segments
		if variables.count == 1, let first = variables.first, case .explode = first.modifier {
			var segValue = ""
			while currentIndex < url.endIndex {
				let ch = url[currentIndex]
				if ch == "/" || ch == "?" || ch == "#" {
					segValue.append(ch == "/" ? "," : "")
					if ch == "/" {
						currentIndex = url.index(after: currentIndex)
						consumedLength += 1
						continue
					}
					break
				}
				segValue.append(ch)
				currentIndex = url.index(after: currentIndex)
				consumedLength += 1
			}
			result[first.name] = segValue.trimmingCharacters(in: CharacterSet(charactersIn: ","))
			return (result, consumedLength)
		}
		
		// For multiple variables, each gets its own path segment
		for (index, variable) in variables.enumerated() {
			var segmentValue = ""
			
			// Extract until next slash or end of string
			while currentIndex < url.endIndex {
				let char = url[currentIndex]
				if char == "/" {
					// Found next segment separator
					if index < variables.count - 1 {
						// Not the last variable, consume the slash and continue
						currentIndex = url.index(after: currentIndex)
						consumedLength += 1
						break
					} else {
						// Last variable, don't consume the slash
						break
					}
				} else if CharacterSet(charactersIn: "?#").contains(char.unicodeScalars.first!) {
					// Found query or fragment, stop
					break
				} else {
					segmentValue.append(char)
					currentIndex = url.index(after: currentIndex)
					consumedLength += 1
				}
			}
			
			result[variable.name] = segmentValue
			
			// If we've reached the end of the URL and there are more variables, stop
			if currentIndex >= url.endIndex && index < variables.count - 1 {
				break
			}
		}
		
		return (result, consumedLength)
	}
	
	private func extractAllPathStyleVariables(
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
			
			var paramIndex = url.index(after: currentIndex) // Skip the ;
			consumedLength += 1
			
			// Extract parameter name
			var paramName = ""
			while paramIndex < url.endIndex && url[paramIndex] != "=" && url[paramIndex] != ";" {
				paramName.append(url[paramIndex])
				paramIndex = url.index(after: paramIndex)
				consumedLength += 1
			}
			
			// Check if this matches our expected variable
			if paramName == variable.name {
				var value = ""
				if paramIndex < url.endIndex && url[paramIndex] == "=" {
					paramIndex = url.index(after: paramIndex) // Skip the =
					consumedLength += 1
					
					// Extract value until ; or end
					while paramIndex < url.endIndex && url[paramIndex] != ";" && url[paramIndex] != "?" && url[paramIndex] != "#" {
						value.append(url[paramIndex])
						paramIndex = url.index(after: paramIndex)
						consumedLength += 1
					}
				}
				
				result[variable.name] = value
				currentIndex = paramIndex
			} else {
				// This parameter doesn't match, backtrack
				currentIndex = url.index(after: currentIndex)
				consumedLength = 1
				
				// Skip to the next semicolon or end
				while currentIndex < url.endIndex && url[currentIndex] != ";" && url[currentIndex] != "?" && url[currentIndex] != "#" {
					currentIndex = url.index(after: currentIndex)
					consumedLength += 1
				}
			}
		}
		
		return result.isEmpty ? nil : (result, consumedLength)
	}
	
	private func extractVariableValue(
		expression: String,
		fromURL url: String,
		startingAt startIndex: String.Index
	) -> (variableName: String, value: String, consumedLength: Int)? {
		
		// Parse the expression
		let (operatorType, variables) = parseExpression(expression)
		
		guard !variables.isEmpty else { return nil }
		
		switch operatorType {
		case .simple:
			return extractSimpleVariable(variables: variables, fromURL: url, startingAt: startIndex)
		case .reserved:
			return extractReservedVariable(variables: variables, fromURL: url, startingAt: startIndex)
		case .label:
			return extractLabelVariable(variables: variables, fromURL: url, startingAt: startIndex)
		case .pathSegment:
			return extractPathSegmentVariable(variables: variables, fromURL: url, startingAt: startIndex)
		case .pathStyle:
			return extractPathStyleVariable(variables: variables, fromURL: url, startingAt: startIndex)
		case .query, .queryContinuation:
			return extractQueryVariable(variables: variables, fromURL: url, startingAt: startIndex)
		case .fragment:
			// Fragments are handled separately in extractFragmentExpression
			return nil
		}
	}
	
	private func extractSimpleVariable(
		variables: [VariableSpec],
		fromURL url: String,
		startingAt startIndex: String.Index
	) -> (variableName: String, value: String, consumedLength: Int)? {
		
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
				return (firstVariable.name, values[0], value.count)
			}
		}
		
		guard let firstVariable = variables.first else { return nil }
		return (firstVariable.name, value, value.count)
	}
	
	private func extractReservedVariable(
		variables: [VariableSpec],
		fromURL url: String,
		startingAt startIndex: String.Index
	) -> (variableName: String, value: String, consumedLength: Int)? {
		
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
		return (firstVariable.name, value, consumedLength)
	}
	
	private func extractLabelVariable(
		variables: [VariableSpec],
		fromURL url: String,
		startingAt startIndex: String.Index
	) -> (variableName: String, value: String, consumedLength: Int)? {
		
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
			if let firstVariable = variables.first, !values.isEmpty {
				return (firstVariable.name, values[0], consumedLength)
			}
		}
		
		guard let firstVariable = variables.first else { return nil }
		return (firstVariable.name, value, consumedLength)
	}
	
	private func extractPathSegmentVariable(
		variables: [VariableSpec],
		fromURL url: String,
		startingAt startIndex: String.Index
	) -> (variableName: String, value: String, consumedLength: Int)? {
		
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
				return (firstVariable.name, values[0], consumedLength)
			}
		}
		
		guard let firstVariable = variables.first else { return nil }
		return (firstVariable.name, value, consumedLength)
	}
	
	private func extractPathStyleVariable(
		variables: [VariableSpec],
		fromURL url: String,
		startingAt startIndex: String.Index
	) -> (variableName: String, value: String, consumedLength: Int)? {
		
		// Path style parameters start with ; and are in format ;name=value
		guard startIndex < url.endIndex && url[startIndex] == ";" else {
			return nil
		}
		
		var currentIndex = url.index(after: startIndex) // Skip the ;
		var consumedLength = 1
		
		// Find the parameter name
		var paramName = ""
		while currentIndex < url.endIndex && url[currentIndex] != "=" && url[currentIndex] != ";" {
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
			while currentIndex < url.endIndex && url[currentIndex] != ";" && url[currentIndex] != "?" && url[currentIndex] != "#" {
				value.append(url[currentIndex])
				currentIndex = url.index(after: currentIndex)
				consumedLength += 1
			}
		}
		
		return (paramName, value, consumedLength)
	}
	
	private func extractQueryVariable(
		variables: [VariableSpec],
		fromURL url: String,
		startingAt startIndex: String.Index
	) -> (variableName: String, value: String, consumedLength: Int)? {
		
		// Query parameters are in format ?name=value or &name=value
		var currentIndex = startIndex
		var consumedLength = 0
		
		// Skip ? or &
		if currentIndex < url.endIndex && (url[currentIndex] == "?" || url[currentIndex] == "&") {
			currentIndex = url.index(after: currentIndex)
			consumedLength += 1
		}
		
		// Find parameter name
		var paramName = ""
		while currentIndex < url.endIndex && url[currentIndex] != "=" && url[currentIndex] != "&" {
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
			while currentIndex < url.endIndex && url[currentIndex] != "&" && url[currentIndex] != "#" {
				value.append(url[currentIndex])
				currentIndex = url.index(after: currentIndex)
				consumedLength += 1
			}
		}
		
		// URL decode the value
		let decodedValue = value.removingPercentEncoding ?? value
		
		return (paramName, decodedValue, consumedLength)
	}
	
	private func extractFromQuery(urlQuery: String?, templateQuery: String, variables: inout [String: String]) -> Bool {
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
	
	private func extractFromFragment(urlFragment: String, templateFragment: String, variables: inout [String: String]) -> Bool {
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
	
	private func parseExpression(_ expression: String) -> (ExpressionOperator, [VariableSpec]) {
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
	
	private func extractQueryExpressions(template: String, url: String, variables: inout [String: String]) -> (remainingTemplate: String, remainingURL: String)? {
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
			remainingTemplate = String(remainingTemplate[..<Range(matchRange, in: remainingTemplate)!.lowerBound]) +
							   String(remainingTemplate[Range(matchRange, in: remainingTemplate)!.upperBound...])
		}
		
		// Remove query part from URL since we've processed it
		let remainingURL = String(urlParts[0])
		
		return (remainingTemplate, remainingURL)
	}
	
	private func extractFragmentExpression(template: String, url: String, variables: inout [String: String]) -> (remainingTemplate: String, remainingURL: String)? {
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
		let remainingTemplate = String(template[..<Range(matchRange, in: template)!.lowerBound]) +
							   String(template[Range(matchRange, in: template)!.upperBound...])
		let remainingURL = String(urlParts[0])
		
		return (remainingTemplate, remainingURL)
	}
	
	private func parseQueryParameters(_ query: String) -> [String: String] {
		var params: [String: String] = [:]
		let pairs = query.split(separator: "&")
		
		for pair in pairs {
			let components = pair.split(separator: "=", maxSplits: 1)
			if components.count == 2 {
				let key = String(components[0])
				let value = String(components[1]).removingPercentEncoding ?? String(components[1])
				params[key] = value
			} else if components.count == 1 {
				params[String(components[0])] = ""
			}
		}
		
		return params
	}
}

// MARK: - Supporting Types

private enum ExpressionOperator {
	case simple          // {var}
	case reserved        // {+var}
	case fragment        // {#var}
	case label           // {.var}
	case pathSegment     // {/var}
	case pathStyle       // {;var}
	case query           // {?var}
	case queryContinuation // {&var}
}

private struct VariableSpec {
	let name: String
	let modifier: VariableModifier
}

private enum VariableModifier {
	case none
	case prefix(Int)
	case explode
} 
