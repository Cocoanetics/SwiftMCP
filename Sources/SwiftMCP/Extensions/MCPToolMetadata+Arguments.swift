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
	 Enriches a dictionary of arguments with default values for any missing parameters.
	 
	 - Parameters:
	   - arguments: The original arguments dictionary
	 
	 - Returns: A new dictionary with default values added for missing parameters
	 - Throws: MCPToolError if required parameters are missing or if parameter conversion fails
	 */
	public func enrichArguments(_ arguments: [String: Sendable]) throws -> [String: Sendable] {
		// Create a copy of the arguments dictionary
		var enrichedArguments = arguments
		
		// Check for missing required parameters and add default values
		for param in parameters {
			// If we don't have an argument for this parameter
			if enrichedArguments[param.name] == nil {
				// If it has a default value, use it
				if let defaultValue = param.defaultValue {
					enrichedArguments[param.name] = defaultValue
				}
				// If it's required and has no default value, throw an error
				else if param.isRequired {
					throw MCPToolError.missingRequiredParameter(parameterName: param.name)
				}
			}
		}
		
		return enrichedArguments
	}
}
