//
//  JSON+DateEncoding.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 07.04.25.
//

import Foundation

extension JSONEncoder.DateEncodingStrategy {
    static let iso8601WithTimeZone = JSONEncoder.DateEncodingStrategy.custom { date, encoder in
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone.current
        formatter.formatOptions = [.withInternetDateTime, .withTimeZone]
        let string = formatter.string(from: date)
        var container = encoder.singleValueContainer()
        try container.encode(string)
    }
}
