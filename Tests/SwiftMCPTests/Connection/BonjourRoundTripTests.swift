//
//  BonjourRoundTripTests.swift
//  SwiftMCP
//
//  The test that would have caught #162.
//
//  Every unit test around Bonjour is offline — constructor checks and pure string
//  derivation — so a client and a server can drift into browsing and advertising
//  different things while every test stays green. That is exactly what happened:
//  a service-type change split the two sides, and the only symptom in the field
//  was a discovery timeout that pointed at the wrong component.
//
//  These tests put a real registration on the wire and browse for it with the
//  real client path.
//

#if Server && Client && canImport(Network)
import Testing
import Foundation
import Network
@testable import SwiftMCP

@Suite("Bonjour round trip", .serialized)
struct BonjourRoundTripTests {
    /// A name no other test run or real daemon on this machine will publish.
    private func uniqueBaseName() -> String {
        "SwiftMCPTest-\(UUID().uuidString.prefix(8))"
    }

    /// Runs `body` against a started transport, then always tears it down.
    ///
    /// Waits on the actual readiness signal — the registration being confirmed —
    /// rather than sleeping a guessed interval. That is both faster and no longer
    /// a race: a fixed sleep is either wasted time or an intermittent failure, and
    /// on a loaded CI runner it is usually both.
    private func withTransport(
        scope: DiscoveryScope,
        _ body: (TCPBonjourTransport, String) async throws -> Void
    ) async throws {
        let base = uniqueBaseName()
        let transport = TCPBonjourTransport(server: StructCalculator(), instanceName: base, scope: scope)
        try await transport.start()

        let deadline = Date().addingTimeInterval(3)
        while transport.resolvedInstanceName == nil, Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        do {
            try await body(transport, base)
        } catch {
            try? await transport.stop()
            throw error
        }
        try await transport.stop()
    }

    @Test("A local-user server is found by a local-user client")
    func localUserRoundTrip() async throws {
        try await withTransport(scope: .localUser) { transport, base in
            #expect(transport.port != nil)
            #expect(transport.resolvedInstanceName != nil)

            // The whole point: the client derives the same advertised name from
            // the same base name, with no shared state beyond the base string.
            let config = MCPServerTcpConfig(instanceName: base, scope: .localUser, timeout: 5)
            let connection = TCPConnection(config: config)
            try await connection.start()
            await connection.stop()
        }
    }

    @Test("A local-machine server is found by a local-machine client")
    func localMachineRoundTrip() async throws {
        try await withTransport(scope: .localMachine) { _, base in
            let config = MCPServerTcpConfig(instanceName: base, scope: .localMachine, timeout: 5)
            let connection = TCPConnection(config: config)
            try await connection.start()
            await connection.stop()
        }
    }

    @Test("The advertised name is the one the scope derives")
    func advertisedNameMatchesScope() async throws {
        try await withTransport(scope: .localUser) { transport, base in
            #expect(transport.advertisedInstanceName == DiscoveryScope.localUser.instanceName(for: base))
            // No conflict is possible on a unique base name, so the registered
            // name should come back unchanged rather than renamed.
            #expect(transport.resolvedInstanceName == transport.advertisedInstanceName)
        }
    }

    @Test("The TXT record is readable for a local-scope service")
    func localScopeTXTIsResolvable() async throws {
        // NWBrowser cannot deliver TXT for a local-only registration, so this
        // goes through the resolver. If that path regresses, TXT silently
        // becomes unavailable at exactly the scope that is the default.
        try await withTransport(scope: .localUser) { transport, _ in
            let record = await BonjourTXTResolver.resolve(
                instanceName: transport.advertisedInstanceName, scope: .localUser, timeout: 2
            )
            let resolved = try #require(record)
            #expect(resolved.serverName == StructCalculator().serverName)
            #expect(resolved.processID == ProcessIdentity.processID)
            #expect(resolved.isPublisherAlive == true)
        }
    }

    @Test("A wrong name is reported as not-found, not as a hang")
    func wrongNameFailsFast() async throws {
        try await withTransport(scope: .localUser) { _, base in
            let config = MCPServerTcpConfig(instanceName: base + "-absent", scope: .localUser, timeout: 1)
            let connection = TCPConnection(config: config)
            await #expect(throws: MCPServerProxyError.self) {
                try await connection.start()
            }
            await connection.stop()
        }
    }

    @Test("A scope mismatch does not silently resolve")
    func scopeMismatchIsNotFound() async throws {
        // A local-only registration must not be reachable by a client browsing
        // the network scope — if it were, "advertise no wider than you serve"
        // would be a comment rather than a property.
        try await withTransport(scope: .localUser) { _, base in
            let config = MCPServerTcpConfig(instanceName: base, scope: .localNetwork, timeout: 1)
            let connection = TCPConnection(config: config)
            await #expect(throws: MCPServerProxyError.self) {
                try await connection.start()
            }
            await connection.stop()
        }
    }
}
#endif
