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

    private func collectLines(from bytes: [UInt8]) async throws -> [String] {
        let stream = AsyncStream<UInt8> { continuation in
            for byte in bytes {
                continuation.yield(byte)
            }
            continuation.finish()
        }

        var lines: [String] = []
        for try await line in stream.sseLines() {
            lines.append(line)
        }
        return lines
    }

    @Test("Splits lines only at CRLF, LF and CR")
    func splitsOnlyAtSSELineTerminators() async throws {
        let lines = try await collectLines(from: Array("a\r\nb\nc\rd\r\re".utf8))
        #expect(lines == ["a", "b", "c", "d", "", "e"])
    }

    @Test("Keeps U+0085, U+2028 and U+2029 inside a data line")
    func keepsUnicodeLineSeparatorsInDataLine() async throws {
        let json = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"text\":\"a\u{85}b\u{2028}c\u{2029}d\"}}"
        let bytes = Array("id: 1\ndata: \(json)\n\n".utf8)

        let lines = try await collectLines(from: bytes)
        #expect(lines == ["id: 1", "data: \(json)", ""])

        let stream = AsyncStream<UInt8> { continuation in
            for byte in bytes {
                continuation.yield(byte)
            }
            continuation.finish()
        }
        var messages: [SSEClientMessage] = []
        for try await message in stream.sseLines().sseMessages() {
            messages.append(message)
        }

        let message = try #require(messages.first)
        #expect(messages.count == 1)
        #expect(message.data == json)
        _ = try JSONSerialization.jsonObject(with: Data(message.data.utf8))
    }
}
