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
// Re-exports FoundationNetworking where Foundation lacks URLSession (Linux,
// Android); `RequestChurn` below is compiled on every platform.
import SwiftCross
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

    /// Regression for a connection that outlives the listener (#218).
    ///
    /// Closing the listener first keeps new connections off a dying loop, but a
    /// client holding an SSE stream open across `stop()` kept touching its
    /// channel's loop from the handler task draining the stream — a write, the
    /// post-response check, the engine's `terminate()` — and a touch after
    /// `shutdownGracefully` had closed that loop was NIO's "Cannot schedule
    /// tasks on an EventLoop that has already shut down", announced to become a
    /// forced crash. The adapter now closes every accepted connection and waits
    /// for its handler task before the loops go down; this holds a stream open
    /// across `stop()` and checks the stream ends and the stop stays prompt (the
    /// cancelled drain loop ends the task, not the quiesce timeout).
    @Test("stop() with a live SSE stream closes it before the event loops go down")
    func stopWithLiveSSEStream() async throws {
        #if canImport(FoundationNetworking)
        return
        #else
        for _ in 0..<5 {
            let (transport, baseURL) = try await HTTPTransportTestHelpers.startTransport()
            let urlSession = URLSession(configuration: .ephemeral)
            let (sessionID, _) = try await HTTPTransportTestHelpers.initializeSession(
                url: baseURL.appendingPathComponent("mcp"), urlSession: urlSession
            )
            let request = HTTPTransportTestHelpers.generalSSERequest(
                url: baseURL.appendingPathComponent("mcp"), sessionID: sessionID
            )
            let capture = HTTPTransportTestHelpers.openStreamingRequest(request, urlSession: urlSession)
            let opened = await HTTPTransportTestHelpers.waitForCondition {
                capture.response.value?.statusCode == 200
            }
            #expect(opened, "The SSE stream opened before stop()")

            let started = DispatchTime.now().uptimeNanoseconds
            try await transport.stop()
            let elapsed = TimeInterval(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000_000
            #expect(
                elapsed < NIOHTTPServerAdapter.slowHandlerWarningDelay,
                "stop() ended the drain loop by cancellation instead of waiting on it"
            )

            // The connection was closed server-side: the client's stream ends
            // on its own, without the watchdog having to cancel the read.
            let timedOut = HTTPTransportBox(false)
            let watchdog = Task {
                try await Task.sleep(nanoseconds: 10_000_000_000)
                timedOut.value = true
                capture.task.cancel()
            }
            _ = await capture.task.result
            watchdog.cancel()
            #expect(!timedOut.value, "stop() closed the SSE connection")
        }
        #endif
    }

    /// The issue's own shape (#218): a client that re-initializes the moment its
    /// connection drops, so an `initialize` — answered on an SSE-framed response
    /// stream — is in flight on an accepted connection while `stop()` runs. Its
    /// drain loop writes the stream's end, and its post-response check executes
    /// on the loop, after the response completes; before the quiesce, either
    /// could land on a loop `shutdownGracefully` had already closed.
    @Test("stop() under request churn neither crashes nor leaves a late response to a closed loop")
    func stopUnderRequestChurn() async throws {
        #if canImport(FoundationNetworking)
        return
        #else
        for _ in 0..<10 {
            let (transport, baseURL) = try await HTTPTransportTestHelpers.startTransport()
            let churn = RequestChurn(url: baseURL.appendingPathComponent("mcp"), workers: 4)
            churn.start()
            try await Task.sleep(nanoseconds: 20_000_000)
            try await transport.stop()
            await churn.stop()
        }
        #endif
    }
}

/// Issues `initialize` requests back to back from several tasks until stopped,
/// so responses are completing on accepted connections throughout `stop()`.
private final class RequestChurn: @unchecked Sendable {
    private let url: URL
    private let workerCount: Int
    private let lock = NSLock()
    private var stopped = false
    private var workers: [Task<Void, Never>] = []

    init(url: URL, workers: Int) {
        self.url = url
        self.workerCount = workers
    }

    func start() {
        workers = (0..<workerCount).map { _ in
            Task { [self] in
                let urlSession = URLSession(configuration: .ephemeral)
                while !isStopped {
                    guard let request = try? HTTPTransportTestHelpers.streamablePOSTRequest(
                        url: url, message: HTTPTransportTestHelpers.initializeRequest()
                    ) else { return }
                    _ = try? await HTTPTransportTestHelpers.readFiniteSSEResponse(request, urlSession: urlSession)
                }
            }
        }
    }

    func stop() async {
        lock.withLock { stopped = true }
        for worker in workers {
            await worker.value
        }
    }

    private var isStopped: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopped
    }
}

/// `SOCK_STREAM` is an enum case on glibc and a plain `Int32` elsewhere.
#if os(Linux) && !canImport(Musl)
private let streamSocketType = Int32(SOCK_STREAM.rawValue)
#else
private let streamSocketType = SOCK_STREAM
#endif

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
        let descriptor = socket(AF_INET, streamSocketType, 0)
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
