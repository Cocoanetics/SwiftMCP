//
//  String+Quotes.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 07.04.25.
//

import Foundation

public extension String {
    var removingQuotes: String {

        guard first == "\"" && last == "\"" else {
            return self
        }

        return String(dropFirst().dropLast())
    }
}
