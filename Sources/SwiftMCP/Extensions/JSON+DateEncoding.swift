//
//  JSON+DateEncoding.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 07.04.25.
//

import Foundation

extension ISO8601DateFormatter: @retroactive @unchecked Sendable {}

extension JSONEncoder.DateEncodingStrategy {
    private static let iso8601Formatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.timeZone = TimeZone.current
    formatter.formatOptions = [.withInternetDateTime, .withTimeZone]
    return formatter
}()

    static let iso8601WithTimeZone = JSONEncoder.DateEncodingStrategy.custom { date, encoder in
    let string = iso8601Formatter.string(from: date)
    var container = encoder.singleValueContainer()
    try container.encode(string)
}
}
