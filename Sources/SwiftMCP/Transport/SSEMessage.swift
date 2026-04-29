import Foundation

/// A Server-Sent Events (SSE) message
struct SSEMessage: LosslessStringConvertible {
    let event: SSEEvent

    var id: String?
    var retry: Int?

    init(event: SSEEvent, id: String? = nil, retry: Int? = nil) {
        self.event = event
        self.id = id
        self.retry = retry
    }

    /// Creates an SSE data message
    /// - Parameters:
    ///   - data: The data content
    ///   - eventName: Optional event name
    ///   - id: Optional event ID
    ///   - retry: Optional reconnect delay in milliseconds
    init(data: String, eventName: String? = nil, id: String? = nil, retry: Int? = nil) {
        self.event = .field(name: "data", value: data, eventName: eventName)
        self.id = id
        self.retry = retry
    }

    /// Creates an SSE comment message
    /// - Parameter comment: The comment text (without the leading colon)
    init(comment: String) {
        self.event = .comment(comment)
        self.id = nil
        self.retry = nil
    }

    /// Creates an SSE field message
    /// - Parameters:
    ///   - name: The field name
    ///   - value: The field value
    ///   - eventName: Optional event name
    ///   - id: Optional event ID
    ///   - retry: Optional reconnect delay in milliseconds
    init(field name: String, value: String, eventName: String? = nil, id: String? = nil, retry: Int? = nil) {
        self.event = .field(name: name, value: value, eventName: eventName)
        self.id = id
        self.retry = retry
    }

    var isReplayableDataEvent: Bool {
        switch event {
        case .comment:
            return false
        case .field(let name, _, _):
            return name == "data"
        }
    }

    /// Creates an SSE message from a string representation
    /// Expects format:
    /// [event: name\n]
    /// data: content\n\n
    init?(_ description: String) {
        let lines = description.split(separator: "\n", omittingEmptySubsequences: false)
        var eventName: String? = nil
        var dataLines: [String] = []
        var eventID: String? = nil
        var retry: Int? = nil

        for line in lines {
            if line.starts(with: "id:") {
                eventID = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            } else if line.starts(with: "retry:") {
                retry = Int(String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces))
            } else if line.starts(with: "event:") {
                eventName = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            } else if line.starts(with: "data:") {
                dataLines.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))
            }
        }

        guard !dataLines.isEmpty else {
            return nil
        }

        self.event = .field(name: "data", value: dataLines.joined(separator: "\n"), eventName: eventName)
        self.id = eventID
        self.retry = retry
    }

    /// Returns the string representation of the message in SSE format
    var description: String {
        switch event {
        case .comment(let comment):
            return ": \(comment)\n"
        case .field(let name, let value, let eventName):
            var message = ""
            if let id {
                message += "id: \(id)\n"
            }
            if let retry {
                message += "retry: \(retry)\n"
            }
            if let eventName = eventName {
                message += "event: \(eventName)\n"
            }
            if value.isEmpty {
                message += "\(name):\n"
            } else {
                let lines = value.split(separator: "\n", omittingEmptySubsequences: false)
                for line in lines {
                    message += "\(name): \(line)\n"
                }
            }
            message += "\n"
            return message
        }
    }
}
