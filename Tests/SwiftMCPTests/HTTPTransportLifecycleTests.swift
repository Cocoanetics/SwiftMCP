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
}
#endif
