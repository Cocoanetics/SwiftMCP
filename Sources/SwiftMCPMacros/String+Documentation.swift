//
//  String+Documentation.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 27.03.25.
//

import Foundation

extension String {
	var removingUnprintableCharacters: String {
		// Create a character set of printable ASCII characters (32-126) plus newline, tab, etc.
		let printableCharacters = CharacterSet(charactersIn: " \t\n\r").union(CharacterSet(charactersIn: UnicodeScalar(32)...UnicodeScalar(126)))
		
		// Filter out any characters that are not in the printable set
		return unicodeScalars.filter { printableCharacters.contains($0) }.map { String($0) }.joined()
	}
	
	/// Escapes a string for use in a Swift string literal.
	/// This handles quotes, backslashes, and other special characters.
	var escapedForSwiftString: String {
		return self
			.replacingOccurrences(of: "\\", with: "\\\\")  // Escape backslashes first
			.replacingOccurrences(of: "\"", with: "\\\"")  // Escape double quotes
			.replacingOccurrences(of: "\'", with: "\\\'")  // Escape single quotes
			.replacingOccurrences(of: "\n", with: "\\n")   // Escape newlines
			.replacingOccurrences(of: "\r", with: "\\r")   // Escape carriage returns
			.replacingOccurrences(of: "\t", with: "\\t")   // Escape tabs
			.replacingOccurrences(of: "\0", with: "\\0")   // Escape null bytes
	}
}
