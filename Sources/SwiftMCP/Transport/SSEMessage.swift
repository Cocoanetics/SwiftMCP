//
//  SSEMessage.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 17.03.25.
//


import Foundation

/// A Server-Sent Events (SSE) message
struct SSEMessage: LosslessStringConvertible {
    let name: String?
    let data: String

    init(name: String? = nil, data: String) {
        self.name = name
        self.data = data
    }

    /// Creates an SSE message from a string representation
    /// Expects format:
    /// [event: name\n]
    /// data: content\n\n
    init?(_ description: String) {
        // Split the message into lines
        let lines = description.split(separator: "\n", omittingEmptySubsequences: false)
        var name: String? = nil
        var data: String? = nil

        for line in lines {
            if line.starts(with: "event:") {
                name = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            } else if line.starts(with: "data:") {
                data = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            }
        }

        // Data field is required
        guard let data = data else {
            return nil
        }

        self.name = name
        self.data = data
    }

    /// Returns the string representation of the message in SSE format
    var description: String {
        var message = ""
        if let name = name {
            message += "event: \(name)\n"
        }
        message += "data: \(data)\n\n"
        return message
    }
}
