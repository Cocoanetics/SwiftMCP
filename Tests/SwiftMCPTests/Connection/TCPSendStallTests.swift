//
//  TCPSendStallTests.swift
//  SwiftMCP
//
//  `TCPBonjourTransport.sendStallTimeout`: a client that has stopped reading is
//  closed once what the server sends it has not moved for the timeout, while one
//  that reads slowly is kept.
//

#if Server && canImport(Network)
import Foundation
import Network
import Testing
@testable import SwiftMCP

@Suite("TCP send stall", .serialized, .timeLimit(.minutes(1)))
struct TCPSendStallTests {
    private static let initializeLine = """
        {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26",\
        "capabilities":{},"clientInfo":{"name":"stall-test","version":"1.0"}}}
        """
    private static let rememberLine = """
        {"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"remember","arguments":{}}}
        """

    /// A started loopback transport for `server` with the stall timeout, and a client
    /// connected to it whose session `server` remembers, for `body`.
    private func withClient(
        stallTimeout: TimeInterval, _ body: (TCPBonjourTransport, TestTCPClient, Session) async throws -> Void
    ) async throws {
        let server = SessionRecorder()
        let transport = TCPBonjourTransport(
            server: server, instanceName: "SwiftMCPTest-\(UUID().uuidString.prefix(8))", scope: .localUser)
        transport.sendStallTimeout = stallTimeout
        try await transport.start()
        do {
            let deadline = Date().addingTimeInterval(5)
            while transport.port == nil, Date() < deadline {
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            let client = try TestTCPClient(port: try #require(transport.port))
            defer { client.closeSocket() }
            await offPool {
                client.send(Self.initializeLine + "\n")
                _ = client.readLine()
                client.send(Self.rememberLine + "\n")
                _ = client.readLine()
            }
            let session = try #require(await server.sessions.all.last)
            try await body(transport, client, session)
        } catch {
            try? await transport.stop()
            throw error
        }
        try await transport.stop()
    }

    /// A log notification of `megabytes` MiB to `session`'s client, sent in a task. Four
    /// are far more than loopback's socket buffers take (some 600 KB), and little enough not to
    /// hold up the suites that run beside this one.
    private static func flood(_ session: Session, megabytes: Int) -> Task<Void, Never> {
        Task {
            await session.work { session in
                await session.sendLogNotification(
                    LogMessage(level: .info, data: .string(String(repeating: "x", count: megabytes << 20))))
            }
        }
    }

    @Test("A client that stops reading is closed once the output has not moved for the timeout")
    func stoppedReaderIsClosed() async throws {
        try await withClient(stallTimeout: 0.5) { transport, client, session in
            let flood = Self.flood(session, megabytes: 4)
            // The send has begun: its first bytes are here. The client reads no more.
            #expect(await offPool { client.readBytes(1024) } == 1024)

            #expect(await FloodOutcome.finishes(flood, within: 10), "the send still waits for a client that stopped")
            #expect(await offPool { client.readsToEndOfFile() }, "the client's connection is still open")
            #expect(await !transport.sessionManager.sessionIDs.contains(session.id))
        }
    }

    @Test("A client that reads slowly is kept, however long the whole message takes")
    func slowReaderIsKept() async throws {
        try await withClient(stallTimeout: 2) { _, client, session in
            // 8 MiB at about 1.3 MB/s: some five seconds for the one message, however much the
            // socket buffers take. Each read takes 256 KiB, so that it opens the client's receive
            // window at once: reads of a few TCP segments may wait for a delayed acknowledgment,
            // or the stack's zero-window probe 5 s on, before the server can send again.
            let flood = Self.flood(session, megabytes: 8)
            let received = await offPool {
                var received = 0
                while received < 8 << 20 {
                    let got = client.readBytes(256 << 10)
                    guard got > 0 else { break }
                    received += got
                    usleep(200_000)
                }
                return received
            }
            #expect(received >= 8 << 20, "the connection closed after \(received) bytes")
            #expect(await FloodOutcome.finishes(flood, within: 10))
            let pong = await offPool {
                _ = client.readLine()  // the rest of the notification's line
                client.send(#"{"jsonrpc":"2.0","id":7,"method":"ping"}"# + "\n")
                return client.readLine()
            }
            #expect(pong?.contains(#""id":7"#) == true, "the client was closed")
        }
    }

    @Test("Stopping the transport stops each connection's stall watch")
    func stoppingTheTransportStopsTheWatch() async throws {
        try await withClient(stallTimeout: 0.5) { transport, _, session in
            let output = try #require(await transport.state.entry(for: session.id)?.output)
            #expect(!output.isFinished)
            try await transport.stop()
            #expect(output.isFinished, "the watch outlived the transport's stop")
        }
    }

    @Test("What the client sends counts as progress, as Node counts a socket's reads")
    func sendingClientIsKept() async throws {
        try await withClient(stallTimeout: 1) { transport, client, session in
            let flood = Self.flood(session, megabytes: 4)
            #expect(await offPool { client.readBytes(1024) } == 1024)
            // Reading nothing, but sending every 100 ms for 2.5 s: past the timeout twice over.
            await offPool {
                for index in 0..<25 {
                    client.send(#"{"jsonrpc":"2.0","method":"notifications/progress","params":"# +
                        #"{"progressToken":\#(index),"progress":1}}"# + "\n")
                    usleep(100_000)
                }
            }
            #expect(await transport.sessionManager.sessionIDs.contains(session.id), "closed while the client sent")
            // Silent now: closed once the timeout passes.
            #expect(await FloodOutcome.finishes(flood, within: 10), "the send still waits for a client that stopped")
            #expect(await !transport.sessionManager.sessionIDs.contains(session.id))
        }
    }
}

/// Whether a task finishes within a bound.
private enum FloodOutcome {
    static func finishes(_ task: Task<Void, Never>, within seconds: Double) async -> Bool {
        let outcome = FirstBool()
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

/// Resumes its continuation with the first outcome given, once.
private final class FirstBool: @unchecked Sendable {
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
