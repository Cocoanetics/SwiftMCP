//
//  SSEMessage.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 17.03.25.
//


import Foundation

/// Represents the different types of SSE content as defined by the ABNF specification
enum SSEEvent {
    /// A comment line starting with colon
    case comment(String)
    
    /// A field with name and value
    case field(name: String, value: String, eventName: String? = nil)
}

/// A Server-Sent Events (SSE) message
struct SSEMessage: LosslessStringConvertible {
    let event: SSEEvent
    
    init(event: SSEEvent) {
        self.event = event
    }
    
    /// Creates an SSE data message
    /// - Parameters:
    ///   - data: The data content
    ///   - eventName: Optional event name
    init(data: String, eventName: String? = nil) {
        self.event = .field(name: "data", value: data, eventName: eventName)
    }
    
    /// Creates an SSE comment message
    /// - Parameter comment: The comment text (without the leading colon)
    init(comment: String) {
        self.event = .comment(comment)
    }
    
    /// Creates an SSE field message
    /// - Parameters:
    ///   - name: The field name
    ///   - value: The field value
    ///   - eventName: Optional event name
    init(field name: String, value: String, eventName: String? = nil) {
        self.event = .field(name: name, value: value, eventName: eventName)
    }
    
    /// Creates an SSE message from a string representation
    /// Expects format:
    /// [event: name\n]
    /// data: content\n\n
    init?(_ description: String) {
        // Split the message into lines
        let lines = description.split(separator: "\n", omittingEmptySubsequences: false)
        var eventName: String? = nil
        var data: String? = nil

        for line in lines {
            if line.starts(with: "event:") {
                eventName = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            } else if line.starts(with: "data:") {
                data = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            }
        }

        // Data field is required
        guard let data = data else {
            return nil
        }

        self.event = .field(name: "data", value: data, eventName: eventName)
    }

    /// Returns the string representation of the message in SSE format
    var description: String {
        switch event {
        case .comment(let comment):
            return ": \(comment)\n"
        case .field(let name, let value, let eventName):
            var message = ""
            if let eventName = eventName {
                message += "event: \(eventName)\n"
            }
            message += "\(name): \(value)\n\n"
            return message
        }
    }
}
