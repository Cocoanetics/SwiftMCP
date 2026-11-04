#if Server
import Testing
import Foundation
import Logging
@testable import SwiftMCP

/// A server with tools and resources but no prompts, so a listen filter's
/// `promptsListChanged` is narrowed away.
@MCPServer(name: "LineListen", version: "1.0")
actor LineListenTestServer {
    /// A subscribable resource.
    @MCPResource("line://status")
    func status() -> String {
        "ok"
    }

    /// Echoes its input.
    /// - Parameter text: The text to echo.
    /// - Returns: The same text.
    @MCPTool(description: "Echoes its input")
    func echo(text: String) -> String { text }
}

/// Modern `subscriptions/listen` on a line transport: the connection carries the
/// notifications, filtered and tagged by the session's subscription.
@Suite("Line-transport subscriptions/listen")
struct LineSubscriptionsListenTests {
    private static let logger = Logger(label: "test.line-listen")

    private let modernMeta: JSONValue = .object(["io.modelcontextprotocol/protocolVersion": .string("2026-07-28")])

    private func listen(id: Int, _ notifications: JSONValue) -> JSONRPCMessage {
        .request(id: id, method: "subscriptions/listen", params: .object([
            "_meta": modernMeta,
            "notifications": notifications
        ]))
    }

    private let fullFilter: JSONValue = .object([
        "toolsListChanged": .bool(true),
        "promptsListChanged": .bool(true),
        "resourceSubscriptions": .array([.string("line://status")])
    ])

    @Test("A listen is acknowledged with the honored filter; notifications are filtered and tagged")
    func acknowledgedFilteredAndTagged() async throws {
        let server = LineListenTestServer()
        let transport = InMemoryTransport()
        let serveTask = Task {
            try await server.serve(over: [transport], gracefulShutdownSignals: [], logger: Self.logger)
        }
        let connection = transport.accept()
        var outbound = connection.outbound.makeAsyncIterator()

        connection.clientSends([listen(id: 5, fullFilter)])
        let ackFrame = try #require(await outbound.next())
        guard case .notification(let ack) = ackFrame.first else {
            Issue.record("expected the acknowledgement first, got \(ackFrame)")
            transport.stop()
            return
        }
        #expect(ack.method == "notifications/subscriptions/acknowledged")
        #expect(ack.params?["_meta"]?[MCPMetaKey.subscriptionId]?.intValue == 5)
        #expect(ack.params?["notifications"]?["toolsListChanged"]?.boolValue == true)
        #expect(ack.params?["notifications"]?["promptsListChanged"] == nil)   // no prompts capability
        #expect(ack.params?["notifications"]?["resourceSubscriptions"]?.arrayValue?.count == 1)

        let session = transport.session
        #expect(await session.isSubscribedToResource(uri: "line://status"))
        try await session.sendPromptListChanged()                                   // filtered
        try await session.sendResourceUpdated(uri: try #require(URL(string: "line://other")))   // filtered
        try await session.sendToolListChanged()
        try await session.sendResourceUpdated(uri: try #require(URL(string: "line://status")))

        let first = try #require(await outbound.next()).first
        let second = try #require(await outbound.next()).first
        guard case .notification(let tools) = first, case .notification(let updated) = second else {
            Issue.record("expected two notifications, got \(String(describing: first)), \(String(describing: second))")
            transport.stop()
            return
        }
        #expect(tools.method == "notifications/tools/list_changed")
        #expect(tools.params?["_meta"]?[MCPMetaKey.subscriptionId]?.intValue == 5)
        #expect(updated.method == "notifications/resources/updated")
        #expect(updated.params?["uri"]?.stringValue == "line://status")
        #expect(updated.params?["_meta"]?[MCPMetaKey.subscriptionId]?.intValue == 5)

        transport.stop()
        try await serveTask.value
    }

    @Test("A newer listen supersedes the previous one, which ends with the empty result")
    func newerListenSupersedes() async throws {
        let server = LineListenTestServer()
        let transport = InMemoryTransport()
        let serveTask = Task {
            try await server.serve(over: [transport], gracefulShutdownSignals: [], logger: Self.logger)
        }
        let connection = transport.accept()
        var outbound = connection.outbound.makeAsyncIterator()

        connection.clientSends([listen(id: 5, fullFilter)])
        _ = await outbound.next()   // acknowledgement of 5
        connection.clientSends([listen(id: 6, .object(["toolsListChanged": .bool(true)]))])

        let completion = try #require(await outbound.next()).first
        guard case .response(let ended) = completion else {
            Issue.record("expected the superseded listen to complete, got \(String(describing: completion))")
            transport.stop()
            return
        }
        #expect(ended.id == .integer(5))
        #expect(ended.result?["resultType"]?.stringValue == "complete")

        let ackFrame = try #require(await outbound.next()).first
        guard case .notification(let ack) = ackFrame else {
            Issue.record("expected the new acknowledgement, got \(String(describing: ackFrame))")
            transport.stop()
            return
        }
        #expect(ack.params?["_meta"]?[MCPMetaKey.subscriptionId]?.intValue == 6)
        #expect(!(await transport.session.isSubscribedToResource(uri: "line://status")))

        transport.stop()
        try await serveTask.value
    }

    @Test("An empty listen clears and completes the stored line subscription")
    func emptyListenClears() async throws {
        let server = LineListenTestServer()
        let transport = InMemoryTransport()
        let serveTask = Task {
            try await server.serve(over: [transport], gracefulShutdownSignals: [], logger: Self.logger)
        }
        let connection = transport.accept()
        var outbound = connection.outbound.makeAsyncIterator()

        connection.clientSends([listen(id: 5, fullFilter)])
        _ = await outbound.next()   // acknowledgement of 5
        connection.clientSends([listen(id: 6, .object([:]))])

        guard case .response(let previous) = try #require(await outbound.next()).first else {
            Issue.record("expected the previous listen to complete")
            transport.stop()
            return
        }
        #expect(previous.id == .integer(5))
        guard case .notification(let acknowledgement) = try #require(await outbound.next()).first else {
            Issue.record("expected the empty listen acknowledgement")
            transport.stop()
            return
        }
        #expect(acknowledgement.params?["notifications"] == .object([:]))
        guard case .response(let cleared) = try #require(await outbound.next()).first else {
            Issue.record("expected the empty listen to complete")
            transport.stop()
            return
        }
        #expect(cleared.id == .integer(6))
        #expect(!(await transport.session.isSubscribedToResource(uri: "line://status")))

        transport.stop()
        try await serveTask.value
    }

    @Test("A legacy (non-modern) subscriptions/listen is an unknown method")
    func legacyListenRejected() async throws {
        let server = LineListenTestServer()
        let transport = InMemoryTransport()
        let serveTask = Task {
            try await server.serve(over: [transport], gracefulShutdownSignals: [], logger: Self.logger)
        }
        let connection = transport.accept()
        var outbound = connection.outbound.makeAsyncIterator()

        connection.clientSends([.request(id: 1, method: "initialize", params: .object([
            "protocolVersion": .string("2025-11-25"),
            "capabilities": .object([:]),
            "clientInfo": .object(["name": .string("TestClient"), "version": .string("1.0")])
        ]))])
        _ = await outbound.next()
        connection.clientSends([.request(id: 2, method: "subscriptions/listen", params: .object([
            "notifications": .object(["toolsListChanged": .bool(true)])
        ]))])

        let frame = try #require(await outbound.next()).first
        guard case .errorResponse(let error) = frame else {
            Issue.record("expected -32601, got \(String(describing: frame))")
            transport.stop()
            return
        }
        #expect(error.error.code == -32601)

        transport.stop()
        try await serveTask.value
    }
}
#endif
