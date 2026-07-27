import Testing
import Foundation
@testable import SwiftMCP

#if Server
/// A port that becomes known later, standing in for an ephemeral HTTP sibling.
private final class LockedPort: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Int?
    var value: Int? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

@Suite("Decoupled transport construction")
struct ConnectionTransportConstructionTests {
    @Test("A decoupled stdio transport has no server")
    func stdioServerless() {
        let transport = StdioTransport()
        #expect(transport.server == nil)
        // It is an `MCPTransport` ready for `serve(over:)` to connect a dispatcher.
        let _: any MCPTransport = transport
    }

    @Test("A server-coupled stdio transport keeps its server")
    func stdioServerCoupled() {
        let transport = StdioTransport(server: StructCalculator())
        #expect(transport.server != nil)
    }

    @Test("A decoupled TCP transport advertises the one service type")
    func tcpServerless() {
        let transport = TCPBonjourTransport(instanceName: "acpx")
        #expect(transport.server == nil)
        #expect(transport.instanceName == "acpx")
        #expect(TCPBonjourTransport.serviceType == MCPBonjour.serviceType)
        let _: any MCPTransport = transport
    }

    @Test("A server-coupled TCP transport takes its base name from the server")
    func tcpServerCoupled() {
        let transport = TCPBonjourTransport(server: StructCalculator())
        #expect(transport.server != nil)
        #expect(transport.baseInstanceName == StructCalculator().serverName)
    }

    @Test("The scope decorates the advertised instance name")
    func scopeDerivesInstanceName() {
        let user = TCPBonjourTransport(instanceName: "Post", scope: .localUser)
        let machine = TCPBonjourTransport(instanceName: "Post", scope: .localMachine)
        let network = TCPBonjourTransport(instanceName: "Post", scope: .localNetwork)

        #expect(user.advertisedInstanceName == "Post (\(DiscoveryScope.userLabel))")
        #expect(machine.advertisedInstanceName == "Post")
        #expect(network.advertisedInstanceName == "Post on \(DiscoveryScope.hostLabel)")
    }

    @Test("A pid is advertised only where it means something")
    func processIDOnlyForLocalScopes() {
        // Across hosts a pid names nothing locally, so publishing one would invite
        // a liveness check that confidently answers about an unrelated process.
        #expect(TCPBonjourTransport(instanceName: "Post", scope: .localUser).txtRecord.processID != nil)
        #expect(TCPBonjourTransport(instanceName: "Post", scope: .localMachine).txtRecord.processID != nil)
        #expect(TCPBonjourTransport(instanceName: "Post", scope: .localNetwork).txtRecord.processID == nil)
    }

    @Test("Declared metadata reaches the TXT record in the decoupled mode")
    func decoupledTXTMetadata() {
        let transport = TCPBonjourTransport(
            instanceName: "mc", serverName: "MissionControl", serverVersion: "1.2.3"
        )
        #expect(transport.txtRecord.serverName == "MissionControl")
        #expect(transport.txtRecord.serverVersion == "1.2.3")
        #expect(transport.txtRecord[BonjourTXTRecord.Key.txtVersion] == BonjourTXTRecord.layoutVersion)
    }

    @Test("serve(over:) fills in server identity and the sibling HTTP endpoint")
    func advertiseFillsDecoupledGaps() {
        // The decoupled transport has no server to read TXT metadata from, and it
        // cannot know where a sibling transport serves the same server.
        let transport = TCPBonjourTransport(instanceName: "mc")
        #expect(transport.txtRecord.serverVersion == nil)
        #expect(transport.txtRecord.httpEndpoint == nil)

        transport.advertise(server: StructCalculator(), httpEndpoint: { "8090/mcp" })

        #expect(transport.txtRecord.serverName == StructCalculator().serverName)
        #expect(transport.txtRecord.serverVersion == StructCalculator().serverVersion)
        #expect(transport.txtRecord.httpEndpoint == "8090/mcp")
    }

    @Test("The HTTP endpoint is resolved late, not snapshotted")
    func httpEndpointResolvesLazily() {
        // A sibling on an ephemeral port has no real port when serve(over:) wires
        // the transports together. Reading it eagerly would omit `http` forever.
        let boundPort = LockedPort()
        let transport = TCPBonjourTransport(instanceName: "mc")
        transport.advertise(server: StructCalculator(), httpEndpoint: {
            boundPort.value.map { "\($0)/mcp" }
        })

        #expect(transport.txtRecord.httpEndpoint == nil)
        boundPort.value = 8090
        #expect(transport.txtRecord.httpEndpoint == "8090/mcp")
    }
}
#endif

@Suite("Discovery scope")
struct DiscoveryScopeTests {
    @Test("Local scopes keep the service off the network")
    func localScopesAreLocalOnly() {
        #expect(DiscoveryScope.localUser.isLocalOnly)
        #expect(DiscoveryScope.localMachine.isLocalOnly)
        #expect(!DiscoveryScope.localNetwork.isLocalOnly)
    }

    @Test("Only the local scopes derive a name a client can reconstruct")
    func nameDerivability() {
        // `.localNetwork` qualifies with the server's own host, which a remote
        // client cannot know — it matches the TXT `name` entry instead.
        #expect(DiscoveryScope.localUser.canDeriveInstanceName)
        #expect(DiscoveryScope.localMachine.canDeriveInstanceName)
        #expect(!DiscoveryScope.localNetwork.canDeriveInstanceName)
    }

    @Test("The user scope separates accounts that would otherwise collide")
    func localUserDisambiguates() {
        // Instance names are machine-wide: two accounts advertising the same base
        // name would collide, and the loser's client would bind to the winner.
        let perUser = DiscoveryScope.localUser.instanceName(for: "Post")
        #expect(perUser != DiscoveryScope.localMachine.instanceName(for: "Post"))
        #expect(perUser.contains(DiscoveryScope.userLabel))
    }

    @Test("Instance-name matching is NFC-normalized and locale-independent")
    func instanceNameMatching() {
        #expect("Mission Control".matchesInstanceName("mission control"))
        #expect(!"Mission".matchesInstanceName("Mission Control"))
        // Precomposed é vs. e + combining acute — same name, different bytes.
        #expect("Café".matchesInstanceName("Cafe\u{0301}"))
        // ASCII-only folding: a locale-sensitive compare would fold these together
        // on a Turkish-locale device and pick a different server than elsewhere.
        #expect(!"I".matchesInstanceName("\u{0131}"))
    }
}

@Suite("Bonjour TXT record")
struct BonjourTXTRecordTests {
    @Test("Round-trips through the DNS-SD wire format")
    func wireRoundTrip() {
        let original = BonjourTXTRecord(
            serverName: "Post", serverVersion: "1.4.0",
            protocolVersion: "2026-07-28", processID: 4711, httpEndpoint: "8090/mcp"
        )
        let bytes = original.dnssdBytes
        let decoded = bytes.withUnsafeBufferPointer {
            BonjourTXTRecord.decode(dnssdBytes: $0.baseAddress!, count: $0.count)
        }
        #expect(decoded.serverName == "Post")
        #expect(decoded.serverVersion == "1.4.0")
        #expect(decoded.protocolVersion == "2026-07-28")
        #expect(decoded.processID == 4711)
        #expect(decoded.httpEndpoint == "8090/mcp")
    }

    @Test("Over-long entries are dropped rather than truncated")
    func oversizedEntriesDropped() {
        // A truncated entry decodes as a *different* value, which is worse than
        // an absent one — absent reads as unknown, wrong reads as authoritative.
        let record = BonjourTXTRecord(serverName: String(repeating: "x", count: 300))
        let decoded = record.dnssdBytes.withUnsafeBufferPointer {
            BonjourTXTRecord.decode(dnssdBytes: $0.baseAddress!, count: $0.count)
        }
        #expect(decoded.serverName == nil)
        #expect(decoded[BonjourTXTRecord.Key.txtVersion] == BonjourTXTRecord.layoutVersion)
    }

    @Test("Liveness is unknown when no pid was published")
    func livenessWithoutPID() {
        #expect(BonjourTXTRecord(serverName: "Post").isPublisherAlive == nil)
    }

    #if canImport(Darwin)
    @Test("A published pid resolves to its liveness")
    func livenessWithPID() {
        // Darwin-only: liveness needs `kill(pid, 0)`, and every platform that can
        // actually advertise over Bonjour has it.
        let record = BonjourTXTRecord(serverName: "Post", processID: ProcessIdentity.processID)
        #expect(record.isPublisherAlive == true)
    }
    #endif
}

#if Client
@Suite("TCP Bonjour configuration")
struct TCPBonjourConfigurationTests {
    @Test("Every Bonjour config browses the one service type")
    func clientUsesOneType() {
        #expect(MCPServerTcpConfig().serviceType == MCPBonjour.serviceType)
        #expect(MCPServerTcpConfig(instanceName: "Mission Control").serviceType == MCPBonjour.serviceType)
    }

    @Test("Local scopes derive the name; localNetwork cannot")
    func derivedNames() {
        let user = MCPServerTcpConfig(instanceName: "Post", scope: .localUser)
        #expect(user.derivedInstanceName == DiscoveryScope.localUser.instanceName(for: "Post"))

        let machine = MCPServerTcpConfig(instanceName: "Post", scope: .localMachine)
        #expect(machine.derivedInstanceName == "Post")

        // Remote host qualification is unknowable client-side, so matching falls
        // through to the TXT `name` entry.
        let network = MCPServerTcpConfig(instanceName: "Post", scope: .localNetwork)
        #expect(network.derivedInstanceName == nil)
        #expect(network.baseInstanceName == "Post")
    }

    @Test("A nameless config has no name to derive")
    func namelessConfig() {
        #expect(MCPServerTcpConfig().derivedInstanceName == nil)
        #expect(MCPServerTcpConfig().baseInstanceName == nil)
    }

    @Test("A proxy-inferred name turns a nameless browse into a lookup")
    func proxyInferredName() async {
        let config = MCPServerTcpConfig(scope: .localMachine)
        let proxy = MCPServerProxy(config: .tcp(config: config))
        await proxy.setServiceForTesting("Mission Control")
        let resolved = await proxy.resolveTcpConfig(config)
        #expect(resolved.baseInstanceName == "Mission Control")
        #expect(resolved.scope == .localMachine)
    }
}
#endif

#if Client && canImport(Network)
import Network

@Suite("TCP Bonjour result selection")
struct TCPBonjourResultSelectionTests {
    private func service(
        _ name: String,
        loopback: Bool = true,
        txt: BonjourTXTRecord? = nil
    ) -> TCPConnection.DiscoveredService {
        TCPConnection.DiscoveredService(
            instanceName: name,
            endpoint: .service(name: name, type: MCPBonjour.serviceType, domain: "local.", interface: nil),
            txtRecord: txt,
            isLoopback: loopback
        )
    }

    @Test("A derived name matches the instance name exactly")
    func namedSelection() throws {
        let services = [service("SwiftMCP"), service("Post (oliver)")]
        let match = try TCPConnection.selectService(
            from: services, derivedName: "post (OLIVER)", baseName: "Post", scope: .localUser
        )
        #expect(match?.instanceName == "Post (oliver)")

        // A prefix is not a match — substring matching is how a client ends up on
        // the wrong server.
        #expect(try TCPConnection.selectService(
            from: services, derivedName: "Post", baseName: "Post", scope: .localUser
        ) == nil)
    }

    @Test("Local scopes ignore anything not on loopback")
    func loopbackFilter() throws {
        let offBox = [service("Post (oliver)", loopback: false)]
        #expect(try TCPConnection.selectService(
            from: offBox, derivedName: "Post (oliver)", baseName: "Post", scope: .localUser
        ) == nil)
    }

    @Test("localNetwork matches the TXT name, not the qualified instance name")
    func networkMatchesTXTName() throws {
        let remote = service(
            "Post on Mac-Studio", loopback: false,
            txt: BonjourTXTRecord(serverName: "Post")
        )
        let match = try TCPConnection.selectService(
            from: [remote], derivedName: nil, baseName: "Post", scope: .localNetwork
        )
        #expect(match?.instanceName == "Post on Mac-Studio")
    }

    @Test("Several hosts advertising the same server are ambiguous, not first-wins")
    func networkMultipleHostsAreAmbiguous() {
        // Every host running `Post` publishes the same TXT name and a different
        // qualified instance name. Browse order is not a host-selection mechanism
        // — taking the first would bind to whichever machine answered soonest.
        let hosts = [
            service("Post on Mac-Studio", loopback: false, txt: BonjourTXTRecord(serverName: "Post")),
            service("Post on MacBook", loopback: false, txt: BonjourTXTRecord(serverName: "Post"))
        ]
        #expect(throws: MCPServerProxyError.self) {
            _ = try TCPConnection.selectService(
                from: hosts, derivedName: nil, baseName: "Post", scope: .localNetwork
            )
        }
    }

    @Test("Naming the qualified instance selects one host outright")
    func networkExactInstanceNameWins() throws {
        // The escape hatch from the ambiguity above: name the host you mean.
        let hosts = [
            service("Post on Mac-Studio", loopback: false, txt: BonjourTXTRecord(serverName: "Post")),
            service("Post on MacBook", loopback: false, txt: BonjourTXTRecord(serverName: "Post"))
        ]
        let match = try TCPConnection.selectService(
            from: hosts, derivedName: nil, baseName: "Post on MacBook", scope: .localNetwork
        )
        #expect(match?.instanceName == "Post on MacBook")
    }

    @Test("Missing TXT falls back to the name prefix rather than rejecting")
    func networkFailsOpenWithoutTXT() throws {
        // TXT can arrive after the first browse callback. Treating absent metadata
        // as a mismatch would reject a working server because of a timing race.
        let remote = service("Post on Mac-Studio", loopback: false, txt: nil)
        let match = try TCPConnection.selectService(
            from: [remote], derivedName: nil, baseName: "Post", scope: .localNetwork
        )
        #expect(match?.instanceName == "Post on Mac-Studio")
    }

    @Test("Nameless discovery selects a sole instance")
    func namelessSelection() throws {
        let sole = try TCPConnection.selectService(
            from: [service("Post (oliver)")], derivedName: nil, baseName: nil, scope: .localUser
        )
        #expect(sole != nil)

        #expect(try TCPConnection.selectService(
            from: [], derivedName: nil, baseName: nil, scope: .localUser
        ) == nil)
    }

    @Test("Nameless discovery reports ambiguity instead of guessing")
    func namelessAmbiguity() {
        // Decidable the moment the results arrive — there is nothing to gain by
        // waiting out the timeout and reporting it as "not found".
        #expect(throws: MCPServerProxyError.self) {
            _ = try TCPConnection.selectService(
                from: [service("Post (oliver)"), service("SwiftMCP (oliver)")],
                derivedName: nil, baseName: nil, scope: .localUser
            )
        }
    }

    @Test("A named lookup is never ambiguous")
    func namedLookupIsNeverAmbiguous() throws {
        // mDNS enforces instance-name uniqueness by conflict-renaming, so one
        // exact match is the answer as soon as it appears. That is what lets a
        // named lookup connect without waiting for the browse to settle.
        let services = [service("Post (oliver)"), service("SwiftMCP (oliver)")]
        let match = try TCPConnection.selectService(
            from: services, derivedName: "Post (oliver)", baseName: "Post", scope: .localUser
        )
        #expect(match?.instanceName == "Post (oliver)")
    }
}
#endif

#if Client
extension MCPServerProxy {
    fileprivate func setServiceForTesting(_ service: String) {
        self.service = service
    }
}
#endif
