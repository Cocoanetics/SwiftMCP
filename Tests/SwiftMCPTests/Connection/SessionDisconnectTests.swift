//
//  SessionDisconnectTests.swift
//  SwiftMCP
//
//  A server closing one client's connection (`Session.disconnect()`): the way a
//  server gives up on a client that has stopped reading, with its other clients
//  left connected and what it was sending that client let go.
//

#if Server && canImport(Network)
import Testing
import Foundation
import Network
@testable import SwiftMCP

/// Keeps the session of each client that calls `remember`, in the order they call.
@MCPServer(name: "Recorder")
final class SessionRecorder: @unchecked Sendable {
    let sessions = RecordedSessions()

    @MCPTool(description: "Remembers the calling client's session")
    func remember() async -> String {
        if let session = Session.current { await sessions.add(session) }
        return "remembered"
    }
}

actor RecordedSessions {
    private(set) var all: [Session] = []

    func add(_ session: Session) {
        all.append(session)
    }
}

@Suite("Session disconnect", .serialized)
struct SessionDisconnectTests {
    private static let initializeLine = """
        {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26",\
        "capabilities":{},"clientInfo":{"name":"disconnect-test","version":"1.0"}}}
        """
    private static let rememberLine = """
        {"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"remember","arguments":{}}}
        """

    /// A loopback TCP transport for `server`, started, its port known, for `body`.
    private func withStartedTransport(
        server: some MCPServer, _ body: (UInt16) async throws -> Void
    ) async throws {
        let transport = TCPBonjourTransport(
            server: server, instanceName: "SwiftMCPTest-\(UUID().uuidString.prefix(8))", scope: .localUser)
        try await transport.start()
        let deadline = Date().addingTimeInterval(5)
        while transport.port == nil, Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        do {
            try await body(try #require(transport.port))
        } catch {
            try? await transport.stop()
            throw error
        }
        try await transport.stop()
    }

    /// A client connected to `port`, initialized, whose session `server` remembers.
    private func rememberedClient(
        _ server: SessionRecorder, port: UInt16
    ) async throws -> (TestTCPClient, Session) {
        let client = try TestTCPClient(port: port)
        await offPool {
            client.send(Self.initializeLine + "\n")
            _ = client.readLine()
            client.send(Self.rememberLine + "\n")
            _ = client.readLine()
        }
        let session = try #require(await server.sessions.all.last)
        return (client, session)
    }

    @Test("Disconnecting a session closes that client's connection, and no other")
    func disconnectClosesOneConnection() async throws {
        let server = SessionRecorder()
        try await withStartedTransport(server: server) { port in
            let (first, session) = try await rememberedClient(server, port: port)
            defer { first.closeSocket() }
            let (second, _) = try await rememberedClient(server, port: port)
            defer { second.closeSocket() }

            await session.disconnect()

            #expect(await offPool { first.readsToEndOfFile() }, "the disconnected client's connection is still open")
            let pong = await offPool {
                second.send(#"{"jsonrpc":"2.0","id":7,"method":"ping"}"# + "\n")
                return second.readLine()
            }
            #expect(pong?.contains(#""id":7"#) == true)
        }
    }

    @Test("A send waiting for a client that stopped reading ends once the client is disconnected")
    func disconnectEndsASendThatWaits() async throws {
        let server = SessionRecorder()
        try await withStartedTransport(server: server) { port in
            let (client, session) = try await rememberedClient(server, port: port)
            defer { client.closeSocket() }
            // Far more than the socket buffers hold (some 600 KB on loopback): once the client
            // stops reading, the send waits for it.
            let flood = Task {
                await session.work { session in
                    await session.sendLogNotification(
                        LogMessage(level: .info, data: .string(String(repeating: "x", count: 4 << 20))))
                }
            }
            // The send has begun: its first bytes are here. The client reads no more.
            #expect(await offPool { client.readBytes(1024) } == 1024)

            await session.disconnect()

            #expect(await Self.finishes(flood, within: 10), "the send still waits for a client that is gone")
        }
    }

    @Test("Disconnecting an HTTP client's session cancels what it runs and removes it")
    func httpDisconnectRemovesTheSession() async throws {
        let transport = HTTPSSETransport(server: SessionRecorder(), port: 0)
        let session = await transport.sessionManager.session(id: UUID())
        #expect(await transport.sessionManager.sessionIDs.contains(session.id))
        let cancelled = CancelCount()
        await session.registerInFlightRequest(id: .integer(9)) { cancelled.count += 1 }

        await session.disconnect()

        #expect(await !transport.sessionManager.sessionIDs.contains(session.id))
        #expect(cancelled.count == 1, "the request in flight was not cancelled")
        #expect(await session.unregisterInFlightRequest(id: .integer(9)), "its response is not suppressed")

        // A request admitted before the disconnect holds the session: it gets no stream for it,
        // and it is cancelled as it registers. New requests find no session.
        #expect(await transport.sessionManager.existingSession(id: session.id) == nil)
        #expect(await transport.sessionManager.createStream(for: session, kind: .request) == nil)
        #expect(await session.workUnlessDisconnected({ _ in true }) == nil, "work was admitted after the disconnect")
        let late = CancelCount()
        await session.registerInFlightRequest(id: .integer(10)) { late.count += 1 }
        #expect(late.count == 1, "a request registering after the disconnect was not cancelled")
        #expect(await session.unregisterInFlightRequest(id: .integer(10)))
    }

    /// Whether `task` finishes within `seconds`.
    private static func finishes(_ task: Task<Void, Never>, within seconds: Double) async -> Bool {
        let outcome = FirstOutcome()
        return await withCheckedContinuation { continuation in
            outcome.continuation = continuation
            Task {
                await task.value
                outcome.resume(true)
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { outcome.resume(false) }
        }
    }
}

/// How often a request's cancellation ran.
private final class CancelCount: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var count: Int {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
}

/// Resumes its continuation with the first outcome given, once.
private final class FirstOutcome: @unchecked Sendable {
    private let lock = NSLock()
    var continuation: CheckedContinuation<Bool, Never>?

    func resume(_ outcome: Bool) {
        let waiting = lock.withLock {
            defer { continuation = nil }
            return continuation
        }
        waiting?.resume(returning: outcome)
    }
}
#endif
