import Foundation

/// A Server-Sent Events (SSE) message
struct SSEMessage: LosslessStringConvertible {
    let event: SSEEvent

    /// Optional event ID for Last-Event-ID resumption (MCP 2025-03-26 spec).
    var id: String?

    init(event: SSEEvent, id: String? = nil) {
        self.event = event
        self.id = id
    }

    /// Creates an SSE data message
    /// - Parameters:
    ///   - data: The data content
    ///   - eventName: Optional event name
    ///   - id: Optional event ID for resumption
    init(data: String, eventName: String? = nil, id: String? = nil) {
        self.event = .field(name: "data", value: data, eventName: eventName)
        self.id = id
    }

    /// Creates an SSE comment message
    /// - Parameter comment: The comment text (without the leading colon)
    init(comment: String) {
        self.event = .comment(comment)
        self.id = nil
    }

    /// Creates an SSE field message
    /// - Parameters:
    ///   - name: The field name
    ///   - value: The field value
    ///   - eventName: Optional event name
    init(field name: String, value: String, eventName: String? = nil) {
        self.event = .field(name: name, value: value, eventName: eventName)
        self.id = nil
    }
    
    /// Creates an SSE message from a string representation
    /// Expects format:
    /// [event: name\n]
    /// data: content\n\n
    init?(_ description: String) {
        let lines = description.split(separator: "\n", omittingEmptySubsequences: false)
        var eventName: String? = nil
        var data: String? = nil
        var parsedId: String? = nil

        for line in lines {
            if line.starts(with: "id:") {
                parsedId = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            } else if line.starts(with: "event:") {
                eventName = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            } else if line.starts(with: "data:") {
                data = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            }
        }

        guard let data = data else {
            return nil
        }

        self.event = .field(name: "data", value: data, eventName: eventName)
        self.id = parsedId
    }

    /// Returns the string representation of the message in SSE format
    var description: String {
        switch event {
        case .comment(let comment):
            return ": \(comment)\n"
        case .field(let name, let value, let eventName):
            var message = ""
            if let id = id {
                message += "id: \(id)\n"
            }
            if let eventName = eventName {
                message += "event: \(eventName)\n"
            }
            message += "\(name): \(value)\n\n"
            return message
        }
    }
}
