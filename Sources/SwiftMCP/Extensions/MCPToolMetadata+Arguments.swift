//
//  MCPToolMetadata+Arguments.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 28.03.25.
//

import Foundation

/**
 Extension to provide utility methods for working with MCP tools.
 */
extension MCPToolMetadata {
	/**
	 Enriches a dictionary of arguments with default values and throws an error if a required parameter is missing.
	 
	 - Parameters:
	   - arguments: The dictionary of arguments to enrich
	   - functionName: The name of the function being called (for error messages)
	 
	 - Returns: The enriched dictionary of arguments
	 - Throws: An error if a required parameter is missing
	 */
	public func enrichArguments(_ arguments: [String: Sendable], functionName: String? = nil) throws -> [String: Sendable] {
		var enrichedArguments = arguments
		
		// Add default values for missing parameters
		for param in parameters {
			if enrichedArguments[param.name] == nil {
				if let defaultValue = param.defaultValue {
					enrichedArguments[param.name] = defaultValue
				} else if param.isRequired {
					throw MCPToolError.missingRequiredParameter(parameterName: param.name)
				}
			}
		}
		
		return enrichedArguments
	}
}
