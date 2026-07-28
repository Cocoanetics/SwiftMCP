//
//  TCPTransportTeardownTests.swift
//  SwiftMCP
//
//  Regression tests for #171: the TCP+Bonjour transport leaked one file
//  descriptor per inbound connection (`cleanupConnection` never called
//  `NWConnection.cancel()`), dropped the final unterminated line on every
//  close, kept tool tasks running for disconnected clients, and parked
//  `run()` forever when the listener died.
//
//  Verification counts *descriptors*, never TCP states: a leaked descriptor shows
//  CLOSE_WAIT after a graceful FIN and CLOSED after an RST, and ages between
//  them — an assertion on states passes while leaking.
//

#if Server && canImport(Network)
import Testing
import Foundation
import Network
@testable import SwiftMCP

/// A minimal blocking TCP client on raw POSIX sockets. Deliberately not
/// Network.framework: the tests need deterministic close semantics (FIN on
/// `close`, half-close via `shutdown`) and their own descriptors excluded
/// from what the transport is being measured on.
private struct TestTCPClient {
    let sock: Int32

    init(port: UInt16) throws {
        sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }

        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard result == 0 else {
            let code = errno
            close(sock)
            throw POSIXError(.init(rawValue: code) ?? .EIO)
        }
    }

    func send(_ string: String) {
        let bytes = Array(string.utf8)
        var sent = 0
        while sent < bytes.count {
            let written = bytes[sent...].withUnsafeBufferPointer {
                write(sock, $0.baseAddress, $0.count)
            }
            guard written > 0 else { return }
            sent += written
        }
    }

    /// Half-close: FIN the write side while keeping the read side open.
    func shutdownWrite() {
        shutdown(sock, SHUT_WR)
    }

    /// Reads until the first newline (or EOF / receive timeout).
    func readLine() -> String? {
        var received = Data()
        var byte: UInt8 = 0
        while read(sock, &byte, 1) == 1 {
            if byte == 0x0A {
                return String(data: received, encoding: .utf8)
            }
            received.append(byte)
        }
        return received.isEmpty ? nil : String(data: received, encoding: .utf8)
    }

    func closeSocket() {
        close(sock)
    }
}

@Suite("TCP transport teardown", .serialized)
struct TCPTransportTeardownTests {

    // MARK: - Helpers

    private func uniqueBaseName() -> String {
        "SwiftMCPTest-\(UUID().uuidString.prefix(8))"
    }

    /// Starts a loopback transport, waits for its ephemeral port, runs `body`,
    /// and always tears the transport down.
    private func withStartedTransport(
        server: some MCPServer,
        _ body: (TCPBonjourTransport, UInt16) async throws -> Void
    ) async throws {
        let transport = TCPBonjourTransport(
            server: server, instanceName: uniqueBaseName(), scope: .localUser
        )
        try await transport.start()

        let deadline = Date().addingTimeInterval(5)
        while transport.port == nil, Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        do {
            let port = try #require(transport.port)
            try await body(transport, port)
        } catch {
            try? await transport.stop()
            throw error
        }
        try await transport.stop()
    }

    private static let initializeLine = """
        {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26",\
        "capabilities":{},"clientInfo":{"name":"teardown-test","version":"1.0"}}}
        """

    /// Live descriptors in this process, counted the only way that sees leaked
    /// sockets (see `TCPBonjourTransport.descriptorUsage`).
    private func liveDescriptorCount() throws -> Int {
        try #require(TCPBonjourTransport.descriptorUsage()).used
    }

    /// Polls until the process descriptor count drops to `ceiling` or below.
    private func waitForDescriptorCount(atMost ceiling: Int, timeout: TimeInterval = 10) async throws -> Int {
        let deadline = Date().addingTimeInterval(timeout)
        var count = try liveDescriptorCount()
        while count > ceiling, Date() < deadline {
            try await Task.sleep(nanoseconds: 100_000_000)
            count = try liveDescriptorCount()
        }
        return count
    }

    // MARK: - §1: the descriptor leak

    @Test("Closed connections release their descriptors")
    func closedConnectionsReleaseDescriptors() async throws {
        try await withStartedTransport(server: StructCalculator()) { _, port in
            // Warm up: the first connection allocates lazy machinery whose
            // descriptors would otherwise pollute the baseline.
            let warmup = try TestTCPClient(port: port)
            warmup.send(Self.initializeLine + "\n")
            _ = warmup.readLine()
            warmup.closeSocket()
            try await Task.sleep(nanoseconds: 300_000_000)

            let baseline = try liveDescriptorCount()
            let connectionCount = 20

            for _ in 0..<connectionCount {
                let client = try TestTCPClient(port: port)
                client.send(Self.initializeLine + "\n")
                _ = client.readLine()
                client.closeSocket()
            }

            // Unrelated suites running in parallel churn a few descriptors, so
            // allow slack well below the leak size: before the fix every one of
            // the 20 connections stranded its sock and the count never came down.
            let tolerance = 5
            let settled = try await waitForDescriptorCount(atMost: baseline + tolerance)
            #expect(
                settled <= baseline + tolerance,
                "descriptors did not return to baseline: \(baseline) before, \(settled) after"
            )
        }
    }

    // MARK: - §4c: the final line on EOF

    @Test("The final unterminated line is processed on half-close")
    func finalLineProcessedOnEOF() async throws {
        try await withStartedTransport(server: StructCalculator()) { _, port in
            let client = try TestTCPClient(port: port)
            defer { client.closeSocket() }

            // No trailing newline; the FIN is what terminates the line.
            client.send(Self.initializeLine)
            client.shutdownWrite()

            let responseLine = try #require(client.readLine())
            let response = try JSONDecoder().decode(
                JSONRPCMessage.self, from: Data(responseLine.utf8)
            )
            #expect(response.id == .integer(1))
        }
    }

    // MARK: - §4a: disconnect cancels in-flight work

    @Test("A client disconnect cancels a running tool")
    func disconnectCancelsRunningTool() async throws {
        let server = HangingServer()
        try await withStartedTransport(server: server) { transport, port in
            // A FIN takes the clean-EOF path, which grants in-flight handlers
            // a drain window before cancelling. Shorten it so the test bounds
            // "cancelled after the grace period", not a 30s default.
            transport.eofDrainTimeout = 0.5

            let client = try TestTCPClient(port: port)

            client.send(Self.initializeLine + "\n")
            _ = client.readLine()

            client.send("""
                {"jsonrpc":"2.0","id":2,"method":"tools/call",\
                "params":{"name":"hang","arguments":{}}}\n
                """)
            #expect(await server.observer.waitUntilStarted())

            client.closeSocket()

            #expect(
                await server.observer.waitUntilCancelled(),
                "the tool kept running after its client disconnected"
            )
        }
    }

    @Test("A half-closing client still receives the reply to an in-flight request")
    func halfCloseKeepsInFlightReply() async throws {
        let server = HangingServer()
        try await withStartedTransport(server: server) { _, port in
            let client = try TestTCPClient(port: port)
            defer { client.closeSocket() }

            client.send(Self.initializeLine + "\n")
            _ = client.readLine()

            // The request arrives in its own receive callback and is still
            // computing when the FIN lands. Teardown must drain it — cancelling
            // here would lose the reply the peer's open read side is waiting for.
            client.send("""
                {"jsonrpc":"2.0","id":2,"method":"tools/call",\
                "params":{"name":"slow","arguments":{}}}\n
                """)
            #expect(await server.observer.waitUntilStarted())
            client.shutdownWrite()

            let responseLine = try #require(client.readLine())
            let response = try JSONDecoder().decode(
                JSONRPCMessage.self, from: Data(responseLine.utf8)
            )
            #expect(response.id == .integer(2))
            #expect(responseLine.contains("slow-done"))
        }
    }

    // MARK: - §2: a dead listener must fail run(), not park it

    @Test("run() throws when the listener fails unrecoverably")
    func runThrowsOnListenerFailure() async throws {
        // Occupy a loopback port so the transport's listener fails its bind.
        // NWListener fails *asynchronously*: start() reports success first, and
        // before the fix the failure was logged and swallowed — run() parked
        // forever with the embedder believing the server was up.
        let blocker = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(blocker) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let bindResult = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(blocker, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        #expect(bindResult == 0)
        #expect(listen(blocker, 1) == 0)

        var boundAddress = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        withUnsafeMutablePointer(to: &boundAddress) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                _ = getsockname(blocker, $0, &length)
            }
        }
        let occupiedPort = UInt16(bigEndian: boundAddress.sin_port)

        let transport = TCPBonjourTransport(
            server: StructCalculator(),
            instanceName: uniqueBaseName(),
            scope: .localUser,
            port: occupiedPort
        )

        await #expect(throws: (any Error).self) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await transport.run()
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: 15_000_000_000)
                    try? await transport.stop()  // unblock run() if it wedged
                    Issue.record("run() did not throw within 15s of the listener failing")
                }
                try await group.next()
                group.cancelAll()
            }
        }
    }

    // MARK: - §4b: accepts racing stop()

    @Test("A connection registered after stop() is refused")
    func connectionAfterStopIsRefused() async throws {
        let transport = TCPBonjourTransport(
            server: StructCalculator(), instanceName: uniqueBaseName(), scope: .localUser
        )

        let connection = NWConnection(
            host: "127.0.0.1", port: .init(rawValue: 9)!, using: .tcp
        )
        defer { connection.cancel() }

        // Never started: not running, so registration must be refused.
        let refusedBeforeStart = await transport.state.addConnection(
            id: UUID(), connection: connection, tasks: ConnectionTaskTracker()
        )
        #expect(refusedBeforeStart == false)

        try await transport.start()
        let id = UUID()
        let acceptedWhileRunning = await transport.state.addConnection(
            id: id, connection: connection, tasks: ConnectionTaskTracker()
        )
        #expect(acceptedWhileRunning == true)

        try await transport.stop()
        #expect(await transport.state.connection(for: id) == nil)

        let refusedAfterStop = await transport.state.addConnection(
            id: UUID(), connection: connection, tasks: ConnectionTaskTracker()
        )
        #expect(refusedAfterStop == false)
    }

    // MARK: - §3: descriptor accounting

    @Test("descriptorUsage counts live descriptors")
    func descriptorUsageCountsLiveDescriptors() throws {
        let before = try #require(TCPBonjourTransport.descriptorUsage())
        #expect(before.used > 0)
        #expect(before.limit > 0)
        #expect(before.used <= before.limit)

        // Ten pipes: twenty descriptors that F_GETFD must see.
        var pipes: [[Int32]] = []
        for _ in 0..<10 {
            var fds: [Int32] = [0, 0]
            #expect(pipe(&fds) == 0)
            pipes.append(fds)
        }
        defer {
            for fds in pipes {
                close(fds[0])
                close(fds[1])
            }
        }

        let after = try #require(TCPBonjourTransport.descriptorUsage())
        #expect(after.used >= before.used + 10)
    }
}
#endif
