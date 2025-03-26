//
//  Array+CaseLabels.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 26.03.25.
//

import Foundation

/**
 An extension on Array that provides functionality for extracting case labels from CaseIterable types.
 
 This extension allows creating an array of strings from the case labels of any type that conforms to CaseIterable.
 The case labels are extracted using the type's string representation, with special handling for cases with associated values.
 
 If the enum conforms to CustomStringConvertible, the case labels will be determined by the custom description implementation.
 This allows for customization of how enum cases are represented in MCP tools.
 */
extension Array where Element == String {
	/**
	 Initialize an array of case labels if the given parameter (a type) conforms to CaseIterable.
	 
	 - Parameters:
	   - type: The type to extract case labels from. Must conform to CaseIterable.
	 
	 - Returns: An array of strings containing the case labels, or nil if the type doesn't conform to CaseIterable.
	 
	 - Note: For cases with associated values, this initializer will extract the case name without the associated values.
	 For example, for a case like `case example(value: Int)`, it will return `"example"`.
	 
	 - Note: If the enum conforms to CustomStringConvertible, the case labels will be determined by the custom description implementation.
	 This allows for customization of how enum cases are represented in MCP tools.
	 */
	public init?<T>(caseLabelsFrom type: T.Type) {
		// Check if T conforms to CaseIterable at runtime.
		guard let caseIterableType = type as? any CaseIterable.Type else {
			return nil
		}
		
		let cases = caseIterableType.allCases
		self = cases.map { caseValue in
			let description = String(describing: caseValue)
			
			// trim off associated value if any
			if let parenIndex = description.firstIndex(of: "(") {
				return String(description[..<parenIndex])
			}
			
			return description
		}
	}
}

extension CaseIterable
{
	static var caseLabels: [String] {
		return self.allCases.map { caseValue in
			let description = String(describing: caseValue)
			
			// trim off associated value if any
			if let parenIndex = description.firstIndex(of: "(") {
				return String(description[..<parenIndex])
			}
			
			return description
		}
	}
}
