#if Server
import Testing
import Foundation
import Logging
@testable import SwiftMCP

/// A small `Sendable` server used to drive `serve(over:)`. Its `shutdown()`
/// records into a shared ``EventLog`` so tests can assert ordering.
@MCPServer(name: "ServeTest", version: "1.0")
actor ServeTestServer {
    let eventLog: EventLog?

    init(eventLog: EventLog? = nil) {
        self.eventLog = eventLog
    }

    /// Echoes its input back to the caller.
    /// - Parameter text: The text to echo.
    /// - Returns: The same text.
    @MCPTool(description: "Echoes its input")
    func echo(text: String) -> String {
        text
    }

    /// Makes a server→client request in the middle of the call, then returns.
    /// - Returns: `"pong-received"` once the client answers.
    @MCPTool(description: "Pings the client mid-call")
    func pingClient() async throws -> String {
        guard let session = Session.current else { return "no-session" }
        let response = try await session.request(method: "ping", params: [:])
        if case .response = response { return "pong-received" }
        return "unexpected"
    }

    func shutdown() async {
        await eventLog?.record("server shutdown")
    }
}

@Suite("serve(over:) routing & lifecycle")
struct ServeOverTransportsTests {
    private static let logger = Logger(label: "test.serve")

    private func initializeRequest(id: Int = 1, version: String = "2025-06-18") -> JSONRPCMessage {
        .request(
            id: id,
            method: "initialize",
            params: [
                "protocolVersion": .string(version),
                "capabilities": .object([:]),
                "clientInfo": .object([
                    "name": .string("TestClient"),
                    "version": .string("1.0")
                ])
            ]
        )
    }

    // MARK: - Routing

    @Test("Routes an initialize request to a response")
    func routesInitialize() async throws {
        let server = ServeTestServer()
        let transport = InMemoryTransport()

        let serveTask = Task {
            try await server.serve(over: [transport], gracefulShutdownSignals: [], logger: Self.logger)
        }

        let connection = transport.accept()
        var outbound = connection.outbound.makeAsyncIterator()
        connection.clientSends([initializeRequest(id: 1)])

        let frame = try #require(await outbound.next())
        guard case .response(let response) = frame.first else {
            Issue.record("Expected an initialize response, got \(String(describing: frame.first))")
            transport.stop()
            return
        }
        #expect(response.id == .integer(1))
        #expect(response.result?["serverInfo"] != nil)

        transport.stop()
        try await serveTask.value
    }

    @Test("Routes a tool call after initialize")
    func routesToolCall() async throws {
        let server = ServeTestServer()
        let transport = InMemoryTransport()

        let serveTask = Task {
            try await server.serve(over: [transport], gracefulShutdownSignals: [], logger: Self.logger)
        }

        let connection = transport.accept()
        var outbound = connection.outbound.makeAsyncIterator()

        connection.clientSends([initializeRequest(id: 1)])
        _ = await outbound.next()   // initialize response frame

        connection.clientSends([
            .request(
                id: 2,
                method: "tools/call",
                params: ["name": .string("echo"), "arguments": .object(["text": .string("hi")])]
            )
        ])

        let frame = try #require(await outbound.next())
        guard case .response(let response) = frame.first else {
            Issue.record("Expected a tool-call response, got \(String(describing: frame.first))")
            transport.stop()
            return
        }
        #expect(response.id == .integer(2))
        let encoded = try JSONEncoder().encode(response.result)
        #expect(String(data: encoded, encoding: .utf8)?.contains("hi") == true)

        transport.stop()
        try await serveTask.value
    }

    @Test("A tool can make a server→client request mid-call")
    func midCallServerRequest() async throws {
        let server = ServeTestServer()
        let transport = InMemoryTransport()

        let serveTask = Task {
            try await server.serve(over: [transport], gracefulShutdownSignals: [], logger: Self.logger)
        }

        let connection = transport.accept()
        var outbound = connection.outbound.makeAsyncIterator()

        connection.clientSends([initializeRequest(id: 1)])
        _ = await outbound.next()   // initialize response

        connection.clientSends([
            .request(
                id: 2,
                method: "tools/call",
                params: ["name": .string("pingClient"), "arguments": .object([:])]
            )
        ])

        // The server emits its own request to us mid-call.
        let serverFrame = try #require(await outbound.next())
        guard case .request(let serverReq) = serverFrame.first, serverReq.method == "ping" else {
            Issue.record("Expected a server→client ping request, got \(String(describing: serverFrame.first))")
            transport.stop()
            return
        }

        // Sequential dispatch would block the read loop inside the tool here; the
        // concurrent pump lets this response through to resume it.
        connection.clientSends([.response(id: serverReq.id, result: [:])])

        let toolFrame = try #require(await outbound.next())
        guard case .response(let data) = toolFrame.first else {
            Issue.record("Expected the tool response, got \(String(describing: toolFrame.first))")
            transport.stop()
            return
        }
        #expect(data.id == .integer(2))
        let encoded = try JSONEncoder().encode(data.result)
        #expect(String(data: encoded, encoding: .utf8)?.contains("pong-received") == true)

        transport.stop()
        try await serveTask.value
    }

    @Test("A request pipelined right after initialize is not spuriously rejected")
    func pipelinedRequestAfterInitialize() async throws {
        let server = ServeTestServer()
        let transport = InMemoryTransport()

        let serveTask = Task {
            try await server.serve(over: [transport], gracefulShutdownSignals: [], logger: Self.logger)
        }

        let connection = transport.accept()
        var outbound = connection.outbound.makeAsyncIterator()

        connection.clientSends([initializeRequest(id: 1)])
        connection.clientSends([.request(id: 2, method: "ping")])

        var sawPingResult = false
        for _ in 0..<2 {
            let frame = try #require(await outbound.next())
            if case .response(let response) = frame.first, response.id == .integer(2) {
                sawPingResult = true
            }
            if case .errorResponse(let error) = frame.first, error.id == .integer(2) {
                Issue.record("ping was rejected: \(error.error.message)")
            }
        }
        #expect(sawPingResult)

        transport.stop()
        try await serveTask.value
    }

    @Test("Rejects requests before initialize")
    func rejectsBeforeInitialize() async throws {
        let server = ServeTestServer()
        let transport = InMemoryTransport()

        let serveTask = Task {
            try await server.serve(over: [transport], gracefulShutdownSignals: [], logger: Self.logger)
        }

        let connection = transport.accept()
        var outbound = connection.outbound.makeAsyncIterator()
        connection.clientSends([.request(id: 7, method: "ping")])

        let frame = try #require(await outbound.next())
        guard case .errorResponse(let error) = frame.first else {
            Issue.record("Expected a rejection error, got \(String(describing: frame.first))")
            transport.stop()
            return
        }
        #expect(error.id == .integer(7))
        #expect(error.error.message == SessionInitializationGate.rejectionMessage)

        transport.stop()
        try await serveTask.value
    }

    @Test("A whole batch round-trips as one frame on a batching protocol version")
    func batchRoundTrips() async throws {
        let server = ServeTestServer()
        let transport = InMemoryTransport()

        let serveTask = Task {
            try await server.serve(over: [transport], gracefulShutdownSignals: [], logger: Self.logger)
        }

        let connection = transport.accept()
        var outbound = connection.outbound.makeAsyncIterator()

        // 2025-03-26 still supports JSON-RPC batching.
        connection.clientSends([initializeRequest(id: 1, version: "2025-03-26")])
        _ = await outbound.next()   // initialize response frame

        connection.clientSends([
            .request(id: 2, method: "ping"),
            .request(id: 3, method: "ping")
        ])

        let frame = try #require(await outbound.next())
        #expect(frame.count == 2)
        #expect(frame.contains { $0.id == .integer(2) })
        #expect(frame.contains { $0.id == .integer(3) })

        transport.stop()
        try await serveTask.value
    }

    @Test("Rejects a batch on a no-batching protocol version")
    func rejectsBatchOnNoBatchingVersion() async throws {
        let server = ServeTestServer()
        let transport = InMemoryTransport()

        let serveTask = Task {
            try await server.serve(over: [transport], gracefulShutdownSignals: [], logger: Self.logger)
        }

        let connection = transport.accept()
        var outbound = connection.outbound.makeAsyncIterator()

        connection.clientSends([initializeRequest(id: 1, version: "2025-06-18")])
        _ = await outbound.next()   // initialize response frame

        connection.clientSends([
            .request(id: 2, method: "ping"),
            .request(id: 3, method: "ping")
        ])

        let frame = try #require(await outbound.next())
        #expect(frame.count == 1)
        guard case .errorResponse(let error) = frame.first else {
            Issue.record("Expected a batch-rejection error, got \(String(describing: frame.first))")
            transport.stop()
            return
        }
        #expect(error.error.code == -32600)

        transport.stop()
        try await serveTask.value
    }

    // MARK: - Lifecycle

    @Test("shutdown() runs after the transports stop")
    func shutdownRunsLast() async throws {
        let eventLog = EventLog()
        let server = ServeTestServer(eventLog: eventLog)
        let transport = InMemoryTransport(label: "memory", eventLog: eventLog)

        let serveTask = Task {
            try await server.serve(over: [transport], gracefulShutdownSignals: [], logger: Self.logger)
        }

        let connection = transport.accept()
        connection.clientDisconnects()
        transport.stop()
        try await serveTask.value

        let events = await eventLog.events
        #expect(events == ["memory stopped", "server shutdown"])
    }

    @Test("shutdown() still runs when a transport fails")
    func shutdownRunsOnFailure() async throws {
        struct BoomError: Error {}
        let eventLog = EventLog()
        let server = ServeTestServer(eventLog: eventLog)
        let transport = InMemoryTransport(label: "memory", eventLog: eventLog, runError: BoomError())

        await #expect(throws: (any Error).self) {
            try await server.serve(over: [transport], gracefulShutdownSignals: [], logger: Self.logger)
        }

        let events = await eventLog.events
        #expect(events.contains("server shutdown"))
    }
}
#endif
