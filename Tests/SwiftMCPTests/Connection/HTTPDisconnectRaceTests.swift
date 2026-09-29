//
//  HTTPDisconnectRaceTests.swift
//  SwiftMCP
//
//  An HTTP request admitted before its client is disconnected (`Session.disconnect()`):
//  it is answered as a request for an unknown session, and runs nothing, however long it
//  was held up after the session check and however many clients went meanwhile.
//

#if Server
import Foundation
import HTTPTypes
import Testing
@testable import SwiftMCP

/// Counts the calls of its one tool.
@MCPServer(name: "CallCounter")
final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    private var rootsChanges = 0

    var count: Int { lock.withLock { calls } }
    var rootsChangesSeen: Int { lock.withLock { rootsChanges } }

    @MCPTool(description: "Counts the call")
    func tally() -> String {
        lock.withLock { calls += 1 }
        return "counted"
    }

    func handleRootsListChanged() async {
        lock.withLock { rootsChanges += 1 }
    }
}

@Suite("HTTP disconnect races", .serialized, .timeLimit(.minutes(1)))
struct HTTPDisconnectRaceTests {
    private static let callLine = """
        {"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"tally","arguments":{}}}
        """

    /// A transport whose one session is initialized, with no token kept for it, and whose
    /// token validation waits at `gate` from now on.
    private static func transport(
        counting counter: CallCounter, gate: ValidationGate
    ) async -> (HTTPSSETransport, Session) {
        let transport = HTTPSSETransport(server: counter, port: 0)
        let session = await transport.sessionManager.session(id: UUID())
        await session.markInitializeRequestReceived()
        transport.oauthConfiguration = OAuthConfiguration(
            issuer: URL(string: "https://example.com")!,
            authorizationEndpoint: URL(string: "https://example.com/auth")!,
            tokenEndpoint: URL(string: "https://example.com/token")!,
            tokenValidator: { _ in await gate.pass() }
        )
        return (transport, session)
    }

    /// `route` run for `session`, held in token validation while the session is disconnected
    /// — and, for `others`, as many other sessions after it.
    private static func racingTheDisconnect(
        of session: Session, on transport: HTTPSSETransport, gate: ValidationGate, others: Int = 0,
        _ route: @escaping @Sendable () async throws -> RouteResponse
    ) async throws -> RouteResponse {
        let call = Task { try await route() }
        #expect(await gate.entered(within: 10), "the request never reached token validation")
        await session.disconnect()
        for _ in 0..<others {
            await transport.sessionManager.session(id: UUID()).disconnect()
        }
        await gate.open()
        return try await call.value
    }

    @Test("A POST admitted before the disconnect is answered 404 and runs nothing")
    func streamablePost() async throws {
        let (counter, gate) = (CallCounter(), ValidationGate())
        let (transport, session) = await Self.transport(counting: counter, gate: gate)

        // More disconnects follow than any list of disconnected sessions would keep.
        let response = try await Self.racingTheDisconnect(of: session, on: transport, gate: gate, others: 65) {
            try await transport.handleStreamableHTTP(request: Self.request(
                .post, "/mcp", body: Self.callLine, session: session.id, accept: "application/json, text/event-stream"))
        }

        #expect(response.status == .notFound)
        #expect(counter.count == 0, "the request ran")
        #expect(await transport.sessionManager.existingSession(id: session.id) == nil, "its id has a session again")
        #expect(await transport.sessionManager.sessionStreams[session.id] == nil, "a stream was opened for it")
    }

    @Test("A notification POST admitted before the disconnect is answered 404 and runs nothing")
    func streamableNotification() async throws {
        let (counter, gate) = (CallCounter(), ValidationGate())
        let (transport, session) = await Self.transport(counting: counter, gate: gate)

        let response = try await Self.racingTheDisconnect(of: session, on: transport, gate: gate) {
            try await transport.handleStreamableHTTP(request: Self.request(
                .post, "/mcp", body: #"{"jsonrpc":"2.0","method":"notifications/roots/list_changed"}"#,
                session: session.id, accept: "application/json, text/event-stream"))
        }

        #expect(response.status == .notFound)
        #expect(counter.rootsChangesSeen == 0, "the notification ran")
    }

    @Test("A GET admitted before the disconnect is answered 404 and opens no stream")
    func streamableGet() async throws {
        let (counter, gate) = (CallCounter(), ValidationGate())
        let (transport, session) = await Self.transport(counting: counter, gate: gate)

        let response = try await Self.racingTheDisconnect(of: session, on: transport, gate: gate) {
            try await transport.handleSSE(request: Self.request(
                .get, "/mcp", body: nil, session: session.id, accept: "text/event-stream"))
        }

        #expect(response.status == .notFound)
        #expect(await transport.sessionManager.sessionStreams[session.id] == nil, "a stream was opened for it")
        #expect(await transport.sessionManager.existingSession(id: session.id) == nil, "its id has a session again")
    }

    @Test("A resuming GET admitted before the disconnect is answered as for an unknown session")
    func streamableResume() async throws {
        let (counter, gate) = (CallCounter(), ValidationGate())
        let (transport, session) = await Self.transport(counting: counter, gate: gate)
        let (_, info) = try #require(await transport.sessionManager.createStream(for: session, kind: .general))

        let response = try await Self.racingTheDisconnect(of: session, on: transport, gate: gate) {
            try await transport.handleSSE(request: Self.request(
                .get, "/mcp", body: nil, session: session.id, accept: "text/event-stream",
                lastEventID: "\(info.streamID.uuidString):1"))
        }

        #expect(response.status == .notFound)
        let body = response.body.flatMap { String(bytes: $0, encoding: .utf8) }
        #expect(body == "Unknown session. Send initialize first.")
        #expect(await transport.sessionManager.streamMeta[info.streamID] == nil, "the stream was taken up again")
        #expect(await transport.sessionManager.existingSession(id: session.id) == nil, "its id has a session again")
    }

    @Test("A legacy POST admitted before the disconnect is answered 404 and runs nothing")
    func legacyPost() async throws {
        let (counter, gate) = (CallCounter(), ValidationGate())
        let (transport, session) = await Self.transport(counting: counter, gate: gate)

        let response = try await Self.racingTheDisconnect(of: session, on: transport, gate: gate) {
            try await transport.handleMessages(request: Self.request(
                .post, "/messages/\(session.id.uuidString)", body: Self.callLine, session: nil,
                accept: "application/json"))
        }

        #expect(response.status == .notFound)
        #expect(counter.count == 0, "the request ran")
        #expect(await transport.sessionManager.existingSession(id: session.id) == nil, "its id has a session again")
    }

    private static func request(
        _ method: HTTPRequest.Method, _ path: String, body: String?, session: UUID?, accept: String,
        lastEventID: String? = nil
    ) -> HTTPRouteRequest<Data?> {
        var fields = HTTPFields()
        fields[.accept] = accept
        fields[.contentType] = "application/json"
        fields[.authorization] = "Bearer token"
        if let session { fields[.mcpSessionID] = session.uuidString }
        if let lastEventID, let name = HTTPField.Name("Last-Event-ID") { fields[name] = lastEventID }
        return HTTPRouteRequest(
            method: method, uri: path, path: path, headerFields: fields, body: body.map { Data($0.utf8) },
            pathParams: [:], queryParams: [])
    }
}

/// Holds each token validation until opened, and says when one is waiting.
private actor ValidationGate {
    private var isOpen = false
    private var validations = 0
    private var held: [CheckedContinuation<Void, Never>] = []
    private var watchers: [CheckedContinuation<Bool, Never>] = []

    /// A validation: it waits until the gate is open, then passes the token.
    func pass() async -> Bool {
        validations += 1
        watchers.forEach { $0.resume(returning: true) }
        watchers = []
        if !isOpen {
            await withCheckedContinuation { held.append($0) }
        }
        return true
    }

    /// Whether a validation began within `seconds`.
    func entered(within seconds: Double) async -> Bool {
        if validations > 0 { return true }
        return await withCheckedContinuation { continuation in
            watchers.append(continuation)
            Task {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                self.giveUp()
            }
        }
    }

    func open() {
        isOpen = true
        held.forEach { $0.resume() }
        held = []
    }

    private func giveUp() {
        watchers.forEach { $0.resume(returning: false) }
        watchers = []
    }
}
#endif
