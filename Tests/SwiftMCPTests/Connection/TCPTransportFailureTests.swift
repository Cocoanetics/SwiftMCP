//
//  TCPTransportFailureTests.swift
//  SwiftMCP
//
//  Failure-mode regression tests for #171: a dead listener must fail `run()`
//  instead of parking it (§2), registration is refused around `stop()` (§4b),
//  and the descriptor watchdog's accounting is sane (§3). The connection
//  teardown behavior lives in `TCPTransportTeardownTests`.
//

#if Server && canImport(Network)
import Testing
import Foundation
import Network
@testable import SwiftMCP

@Suite("TCP transport failure modes", .serialized)
struct TCPTransportFailureTests {

    private func uniqueBaseName() -> String {
        "SwiftMCPTest-\(UUID().uuidString.prefix(8))"
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
        let sanity = try #require(TCPBonjourTransport.descriptorUsage())
        #expect(sanity.used > 0)
        #expect(sanity.limit > 0)
        #expect(sanity.used <= sanity.limit)

        // Fifty pipes: a hundred descriptors that F_GETFD must see. Suites in
        // other files run concurrently and churn this process's descriptor
        // table, so a single before/after pair can race a burst of closes — a
        // single HTTP transport teardown releases dozens of descriptors (its
        // event-loop kqueues, channels, sockets) at once. The signal must
        // outweigh any such burst; the pipes persist across attempts, while
        // churn beating +100 every time doesn't.
        var sawIncrease = false
        for _ in 0..<3 where !sawIncrease {
            let before = try #require(TCPBonjourTransport.descriptorUsage())

            // Seeded with -1, never 0: a failed `pipe` must not leave the pair
            // aliasing stdin, or the cleanup below would close descriptor 0
            // twice and hand a live descriptor number to the second close.
            var pipes: [[Int32]] = []
            for _ in 0..<50 {
                var fds: [Int32] = [-1, -1]
                guard pipe(&fds) == 0 else {
                    Issue.record("pipe() failed with errno \(errno)")
                    break
                }
                pipes.append(fds)
            }
            defer {
                for fds in pipes {
                    close(fds[0])
                    close(fds[1])
                }
            }

            let after = try #require(TCPBonjourTransport.descriptorUsage())
            sawIncrease = after.used >= before.used + 50
        }
        #expect(sawIncrease, "a hundred live pipe descriptors never showed up in the count")
    }
}

@Suite("TCP line partitioning")
struct TCPLinePartitioningTests {

    @Test("Cancellation notifications are split out; lookalikes stay put")
    func partitionCancellations() {
        let cancel = #"{"jsonrpc":"2.0","method":"notifications/cancelled","params":{"requestId":1}}"#
        let request = #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"hang","arguments":{}}}"#
        // Contains the substring but is a request — must not be reordered.
        let lookalike = #"{"jsonrpc":"2.0","id":2,"method":"tools/call","#
            + #""params":{"name":"echo","arguments":{"text":"notifications/cancelled"}}}"#
        let garbage = "not json notifications/cancelled"

        let (cancellations, rest) = TCPBonjourTransport.partitionCancellations(
            [request, lookalike, cancel, garbage]
        )
        #expect(cancellations == [cancel])
        #expect(rest == [request, lookalike, garbage])
    }

    @Test("Batches without cancellations pass through untouched")
    func noCancellations() {
        let lines = ["one", "two"]
        let (cancellations, rest) = TCPBonjourTransport.partitionCancellations(lines)
        #expect(cancellations.isEmpty)
        #expect(rest == lines)
    }
}
#endif
