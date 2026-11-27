//
//  String+Documentation.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 27.03.25.
//

import Foundation

extension String {
    /// Removes control characters (Unicode category Cc), keeping tab, newline and carriage return.
    ///
    /// Everything else is kept, including non-ASCII text such as em dashes, en dashes in
    /// ranges ("1–600"), arrows, accented letters and other scripts: a Swift string literal
    /// holds them as they are, and dropping them changed what descriptions said.
    var removingUnprintableCharacters: String {
        let kept: Set<Unicode.Scalar> = ["\t", "\n", "\r"]
        var result = String.UnicodeScalarView()
        result.append(contentsOf: unicodeScalars.filter {
            $0.properties.generalCategory != .control || kept.contains($0)
        })
        return String(result)
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
