import Testing
import Foundation
@testable import SwiftMCP

@Suite("Line Transport Initialization")
struct LineTransportInitializationTests {
    private func initializeRequest(id: Int = 1) -> JSONRPCMessage {
        .request(
            id: id,
            method: "initialize",
            params: [
                "protocolVersion": .string("2025-11-25"),
                "capabilities": .object([:]),
                "clientInfo": .object([
                    "name": .string("TestClient"),
                    "version": .string("1.0")
                ])
            ]
        )
    }

    private func encodeLine<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601WithTimeZone
        encoder.outputFormatting = [.sortedKeys]
        var data = try encoder.encode(value)
        data.append(0x0A)
        return data
    }

    private func decodeMessages(from line: String) throws -> [JSONRPCMessage] {
        try JSONRPCMessage.decodeMessages(from: Data(line.utf8))
    }

    @Test("Uninitialized session rejects non-initialize requests")
    func uninitializedSessionRejectsNonInitialize() async {
        let session = Session(id: UUID())
        let messages = [JSONRPCMessage.request(id: 1, method: "ping")]

        #expect(await SessionInitializationGate.shouldReject(messages, for: session))
    }

    @Test("Uninitialized session allows batches that start with initialize")
    func uninitializedSessionAllowsInitializeBatch() async {
        let session = Session(id: UUID())
        let messages = [
            initializeRequest(id: 1),
            JSONRPCMessage.request(id: 2, method: "ping")
        ]

        #expect(!(await SessionInitializationGate.shouldReject(messages, for: session)))
    }

    @Test("Rejection responses preserve request IDs")
    func rejectionResponsesPreserveRequestIDs() throws {
        let responses = SessionInitializationGate.rejectionResponses(for: [
            .request(id: 7, method: "ping"),
            .notification(method: "notifications/initialized")
        ])

        #expect(responses.count == 1)
        guard case .errorResponse(let error) = responses[0] else {
            Issue.record("Expected error response")
            return
        }

        #expect(error.id == .int(7))
        #expect(error.error.message == SessionInitializationGate.rejectionMessage)
    }

    @Test("In-process stdio rejects ping before initialize")
    func inProcessStdioRejectsPingBeforeInitialize() async throws {
        let bridge = InProcessStdioBridge(server: LocalStdioServer())
        try await bridge.start()
        defer { Task { await bridge.stop() } }

        let lines = await bridge.lines()
        var iterator = lines.makeAsyncIterator()

        await bridge.write(try encodeLine(JSONRPCMessage.request(id: 1, method: "ping")))

        guard let line = try await iterator.next() else {
            Issue.record("Expected response line")
            return
        }

        let messages = try decodeMessages(from: line)
        #expect(messages.count == 1)

        guard case .errorResponse(let error) = messages[0] else {
            Issue.record("Expected error response")
            return
        }

        #expect(error.id == .int(1))
        #expect(error.error.message == SessionInitializationGate.rejectionMessage)
    }

    @Test("In-process stdio accepts batch when initialize comes first")
    func inProcessStdioAllowsInitializeFirstBatch() async throws {
        let bridge = InProcessStdioBridge(server: LocalStdioServer())
        try await bridge.start()
        defer { Task { await bridge.stop() } }

        let lines = await bridge.lines()
        var iterator = lines.makeAsyncIterator()

        let batch = [
            initializeRequest(id: 1),
            JSONRPCMessage.request(id: 2, method: "ping")
        ]
        await bridge.write(try encodeLine(batch))

        guard let line = try await iterator.next() else {
            Issue.record("Expected response line")
            return
        }

        let messages = try decodeMessages(from: line)
        #expect(messages.count == 2)

        guard case .response(let initializeResponse) = messages[0] else {
            Issue.record("Expected initialize response")
            return
        }

        #expect(initializeResponse.id == .int(1))

        guard case .response(let pingResponse) = messages[1] else {
            Issue.record("Expected ping response")
            return
        }

        #expect(pingResponse.id == .int(2))
    }
}
