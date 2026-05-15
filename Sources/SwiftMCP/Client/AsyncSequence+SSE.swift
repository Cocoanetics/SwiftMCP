import Foundation

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, macCatalyst 15.0, *)
struct SSEMessageSequence<Base: AsyncSequence>: AsyncSequence where Base.Element: StringProtocol {
    typealias Element = SSEClientMessage
    let base: Base

    struct AsyncIterator: AsyncIteratorProtocol {
        var iterator: Base.AsyncIterator
        var currentEvent: String = ""
        var currentDataLines: [String] = []
        var currentID: String?
        var currentRetry: Int?
        var hasPendingFields = false

        mutating func next() async throws -> SSEClientMessage? {
            while let lineValue = try await iterator.next() {
                let line = String(lineValue)
                if let yielded = handleLine(line) {
                    return yielded
                }
            }

            if hasPendingFields {
                return yieldCurrent()
            }

            return nil
        }

        /// Process one raw SSE line; returns a message to yield, or nil to continue.
        private mutating func handleLine(_ line: String) -> SSEClientMessage? {
            if line.isEmpty {
                return hasPendingFields ? yieldCurrent() : nil
            }

            if line.hasPrefix(":") {
                return nil
            }

            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            let field = String(parts[0])
            let rawValue = parts.count > 1 ? String(parts[1]) : ""
            let value = rawValue.hasPrefix(" ") ? String(rawValue.dropFirst()) : rawValue

            return applyField(field, value: value)
        }

        /// Apply a single SSE field to the in-progress message and return a yielded message if complete.
        private mutating func applyField(_ field: String, value: String) -> SSEClientMessage? {
            switch field {
            case "event":
                currentEvent = value
                hasPendingFields = true
            case "data":
                currentDataLines.append(value)
                hasPendingFields = true
                if currentEvent == "endpoint" || value.contains("jsonrpc") || (currentID != nil && value.isEmpty) {
                    return yieldCurrent()
                }
            case "id":
                currentID = value
                hasPendingFields = true
            case "retry":
                currentRetry = Int(value)
                hasPendingFields = true
            default:
                break
            }
            return nil
        }

        private mutating func yieldCurrent() -> SSEClientMessage {
            let message = SSEClientMessage(
                event: currentEvent,
                data: currentDataLines.joined(separator: "\n"),
                id: currentID,
                retry: currentRetry
            )
            currentEvent = ""
            currentDataLines = []
            currentID = nil
            currentRetry = nil
            hasPendingFields = false
            return message
        }
    }

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(iterator: base.makeAsyncIterator())
    }
}

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, macCatalyst 15.0, *)
extension AsyncSequence where Element: StringProtocol {
    /// Transform a sequence of SSE lines into SSEClientMessage objects.
    func sseMessages() -> SSEMessageSequence<Self> {
        SSEMessageSequence(base: self)
    }
}
