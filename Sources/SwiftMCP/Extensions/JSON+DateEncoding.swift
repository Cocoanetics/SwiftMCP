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

extension JSONDecoder.DateDecodingStrategy {
    static let iso8601WithTimeZone = JSONDecoder.DateDecodingStrategy.custom { decoder in
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone.current
        formatter.formatOptions = [.withInternetDateTime, .withTimeZone]
        if let date = formatter.date(from: string) {
            return date
        }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO 8601 date")
    }
}
