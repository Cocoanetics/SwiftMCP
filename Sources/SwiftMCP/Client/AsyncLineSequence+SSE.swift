import Foundation

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, macCatalyst 15.0, *)
extension AsyncLineSequence where Base: Sendable {
    /// Transform an AsyncLineSequence into SSEClientMessage objects.
    func sseMessages() -> AsyncThrowingStream<SSEClientMessage, Error> {
        AsyncThrowingStream { continuation in
            Task { @Sendable in
                do {
                    var currentEvent = ""
                    var currentData = ""

                    for try await line in self {
                        if line.isEmpty {
                            if !currentData.isEmpty {
                                continuation.yield(SSEClientMessage(event: currentEvent, data: currentData))
                                currentEvent = ""
                                currentData = ""
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
                                continuation.yield(SSEClientMessage(event: currentEvent, data: currentData))
                                currentEvent = ""
                                currentData = ""
                            }

                            continue
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
