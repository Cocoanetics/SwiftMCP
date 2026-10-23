//
//  HTTPTransportLifecycleTests.swift
//  SwiftMCP
//
//  Regression tests for #171 §4d: a failed or repeated `start()` leaked the
//  adapter's whole `EventLoopGroup` (coreCount threads + a kqueue descriptor),
//  and a second `start()` stranded the first listener unreachable while the
//  new bind failed EADDRINUSE against it.
//

#if Server
import Testing
import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Android)
import Android
#endif
@testable import SwiftMCP

@Suite("HTTP transport lifecycle", .serialized)
struct HTTPTransportLifecycleTests {

    @Test("start() is idempotent while running")
    func startIsIdempotent() async throws {
        let transport = HTTPSSETransport(server: Calculator(), host: "127.0.0.1", port: 0)
        try await transport.start()
        let boundPort = transport.port
        #expect(boundPort != 0)

        // A second start must be a no-op on the already-bound adapter — not a
        // new adapter racing the old one for the port.
        try await transport.start()
        #expect(transport.port == boundPort)

        try await transport.stop()
    }

    @Test("A failed bind leaves the transport stoppable and restartable")
    func failedBindLeavesTransportRestartable() async throws {
        let occupant = HTTPSSETransport(server: Calculator(), host: "127.0.0.1", port: 0)
        try await occupant.start()
        let occupiedPort = occupant.port

        let transport = HTTPSSETransport(server: Calculator(), host: "127.0.0.1", port: occupiedPort)
        await #expect(throws: (any Error).self) {
            try await transport.start()
        }

        // Nothing bound, so stop() must be safe...
        try await transport.stop()

        // ...and once the port frees up, the same instance can start.
        try await occupant.stop()
        try await transport.start()
        #expect(transport.port == occupiedPort)
        try await transport.stop()
    }

    /// Regression for a shutdown race between the listener and the event loops.
    ///
    /// `shutdownGracefully` closes every loop concurrently, and the listener used
    /// to close only as part of that. A connection the still-open listener
    /// accepted onto a loop that had already finished closing was registered
    /// through `flatSubmit`, whose promise could then never be fulfilled — and
    /// NIO's debug-build leak check kills the process for it ("leaking promise
    /// created at NIOCore/EventLoop.swift"). A client that reconnects the moment
    /// its connection drops turns that into a plain `stop()` crash, so the
    /// adapter now closes the listener first and only then shuts the loops down.
    /// The test keeps connections arriving at the port throughout `stop()`.
    @Test("stop() under connection churn neither crashes nor accepts late connections")
    func stopUnderConnectionChurn() async throws {
        for _ in 0..<15 {
            let transport = HTTPSSETransport(server: Calculator(), host: "127.0.0.1", port: 0)
            try await transport.start()
            let port = transport.port
            let churn = ConnectionChurn(port: port, threads: 4)
            churn.start()
            try await Task.sleep(nanoseconds: 2_000_000)
            try await transport.stop()
            churn.stop()
            // The listener is gone before stop() returns: nothing accepts anymore.
            #expect(!ConnectionChurn.connectOnce(port: port))
        }
    }
}

/// Opens and closes TCP connections to a loopback port from plain threads
/// (blocking socket calls stay off the cooperative pool) until stopped.
///
/// The churn is brief on purpose: every connection it closes parks an ephemeral
/// port in TIME_WAIT for a while, and tens of thousands of them would starve the
/// later loopback tests of source ports.
private final class ConnectionChurn: @unchecked Sendable {
    private let port: Int
    private let threadCount: Int
    private let lock = NSLock()
    private var stopped = false

    init(port: Int, threads: Int) {
        self.port = port
        self.threadCount = threads
    }

    func start() {
        for _ in 0..<threadCount {
            let thread = Thread { [self] in
                while !isStopped {
                    _ = Self.connectOnce(port: port)
                }
            }
            thread.start()
        }
    }

    func stop() {
        lock.lock()
        stopped = true
        lock.unlock()
    }

    private var isStopped: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopped
    }

    /// One blocking connect to 127.0.0.1:`port`; `true` when the handshake
    /// completed, i.e. a listener accepted it.
    static func connectOnce(port: Int) -> Bool {
        let descriptor = socket(AF_INET, Int32(SOCK_STREAM), 0)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(port).bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }
}
#endif
