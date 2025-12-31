import Foundation

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, macCatalyst 15.0, *)
struct SSEMessageSequence<Base: AsyncSequence>: AsyncSequence where Base.Element: StringProtocol {
    typealias Element = SSEClientMessage
    let base: Base

    struct AsyncIterator: AsyncIteratorProtocol {
        var iterator: Base.AsyncIterator
        var currentEvent: String = ""
        var currentData: String = ""

        mutating func next() async throws -> SSEClientMessage? {
            while let lineValue = try await iterator.next() {
                let line = String(lineValue)
                if line.isEmpty {
                    if !currentData.isEmpty {
                        return yieldCurrent()
                    }
                    continue
                }

                if let range = line.range(of: "event: ") {
                    currentEvent = String(line[range.upperBound...])
                    continue
                }

                if let range = line.range(of: "data: ") {
                    currentData = String(line[range.upperBound...])

                    if currentEvent == "endpoint" || currentData.contains("jsonrpc") {
                        return yieldCurrent()
                    }

                    continue
                }
            }

            if !currentData.isEmpty {
                return yieldCurrent()
            }

            return nil
        }

        private mutating func yieldCurrent() -> SSEClientMessage {
            let message = SSEClientMessage(event: currentEvent, data: currentData)
            currentEvent = ""
            currentData = ""
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
