import Testing
import Foundation
@testable import SwiftMCP

@Suite("SSE Parser")
struct SSEParserTests {
    private func collectMessages(from lines: [String]) async throws -> [SSEClientMessage] {
        let stream = AsyncStream<String> { continuation in
            for line in lines {
                continuation.yield(line)
            }
            continuation.finish()
        }

        var messages: [SSEClientMessage] = []
        for try await message in stream.sseMessages() {
            messages.append(message)
        }
        return messages
    }

    @Test("Parses priming events with id and empty data")
    func parsesPrimingEvent() async throws {
        let messages = try await collectMessages(from: [
            "id: stream-1:1",
            "data:",
            ""
        ])

        let message = try #require(messages.first)
        #expect(message.id == "stream-1:1")
        #expect(message.data == "")
        #expect(message.event == "")
        #expect(message.retry == nil)
    }

    @Test("Parses multiline data and retry fields")
    func parsesMultilineData() async throws {
        let messages = try await collectMessages(from: [
            "id: stream-1:2",
            "event: update",
            "retry: 2500",
            "data: first",
            "data: second",
            ""
        ])

        let message = try #require(messages.first)
        #expect(message.id == "stream-1:2")
        #expect(message.event == "update")
        #expect(message.retry == 2500)
        #expect(message.data == "first\nsecond")
    }

    @Test("Parses JSON-RPC single-line payloads without waiting for EOF")
    func parsesJSONRPCPayload() async throws {
        let messages = try await collectMessages(from: [
            "id: stream-1:3",
            "data: {\"jsonrpc\":\"2.0\",\"method\":\"notifications/tools/list_changed\"}"
        ])

        let message = try #require(messages.first)
        #expect(message.id == "stream-1:3")
        #expect(message.data.contains("\"jsonrpc\":\"2.0\""))
    }
}
