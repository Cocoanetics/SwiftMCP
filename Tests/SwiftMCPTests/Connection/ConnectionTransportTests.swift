import Testing
import Foundation
@testable import SwiftMCP

#if Server
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

    @Test("A decoupled TCP transport advertises the base service type")
    func tcpServerless() {
        let transport = TCPBonjourTransport(serviceName: "acpx")
        #expect(transport.server == nil)
        #expect(transport.serviceName == "acpx")
        #expect(transport.serviceType == MCPBonjourServiceType.base)
        #expect(transport.legacyServiceType == MCPBonjourServiceType.forServer("acpx"))
        let _: any MCPTransport = transport
    }

    @Test("A server-coupled TCP transport advertises the base service type")
    func tcpServerCoupled() {
        let transport = TCPBonjourTransport(server: StructCalculator())
        #expect(transport.server != nil)
        #expect(transport.serviceType == MCPBonjourServiceType.base)
        #expect(
            transport.legacyServiceType
                == MCPBonjourServiceType.forServer(StructCalculator().serverName)
        )
    }

    @Test("An explicit TCP service type disables legacy advertisement")
    func tcpCustomServiceType() {
        let transport = TCPBonjourTransport(serviceName: "acpx", serviceType: "_custom._tcp")
        #expect(transport.serviceType == "_custom._tcp")
        #expect(transport.legacyServiceType == nil)
    }
}
#endif

@Suite("TCP Bonjour configuration")
struct TCPBonjourConfigurationTests {
    @Test("Derived service types are DNS-SD safe")
    func sanitizedServiceTypes() {
        #expect(MCPBonjourServiceType.forServer("Post") == "_post-mcp._tcp")
        #expect(MCPBonjourServiceType.forServer("Mission Control") == "_mission-con-mcp._tcp")
        #expect(MCPBonjourServiceType.forServer("  My__Server!!! ") == "_my-server-mcp._tcp")
        #expect(MCPBonjourServiceType.forServer("🌍") == "_server-mcp._tcp")
    }

    #if Client
    @Test("Bonjour configs browse the base type by default")
    func clientUsesBaseType() {
        #expect(MCPServerTcpConfig().serviceType == MCPBonjourServiceType.base)
        #expect(MCPServerTcpConfig(serviceName: "Mission Control").serviceType == MCPBonjourServiceType.base)
        #expect(MCPServerTcpConfig().bonjourServiceTypes == [MCPBonjourServiceType.base])
        #expect(
            MCPServerTcpConfig(serviceName: "Mission Control").bonjourServiceTypes
                == [MCPBonjourServiceType.base, MCPBonjourServiceType.forServer("Mission Control")]
        )
        #expect(
            MCPServerTcpConfig(serviceName: "Mission Control", serviceType: "_legacy._tcp").serviceType
                == "_legacy._tcp"
        )
        #expect(
            MCPServerTcpConfig(
                serviceName: "Mission Control",
                serviceType: "_legacy._tcp"
            ).bonjourServiceTypes == ["_legacy._tcp"]
        )
    }

    @Test("A proxy-inferred name retains the legacy fallback")
    func proxyInferredNameUsesFallback() async {
        let config = MCPServerTcpConfig()
        let proxy = MCPServerProxy(config: .tcp(config: config))
        await proxy.setServiceForTesting("Mission Control")
        let resolved = await proxy.resolveTcpConfig(config)
        #expect(
            resolved.bonjourServiceTypes
                == [MCPBonjourServiceType.base, MCPBonjourServiceType.forServer("Mission Control")]
        )
    }
    #endif
}

#if Client && canImport(Network)
import Network

@Suite("TCP Bonjour result selection")
struct TCPBonjourResultSelectionTests {
    private let missionControl = NWEndpoint.service(
        name: "Mission Control",
        type: MCPBonjourServiceType.base,
        domain: "local.",
        interface: nil
    )
    private let swiftMCP = NWEndpoint.service(
        name: "SwiftMCP",
        type: MCPBonjourServiceType.base,
        domain: "local.",
        interface: nil
    )

    @Test("A configured name matches the instance name exactly")
    func namedSelection() {
        #expect(
            TCPConnection.selectBonjourEndpoint(
                from: [swiftMCP, missionControl],
                serviceName: "mission control"
            ) != nil
        )
        #expect(
            TCPConnection.selectBonjourEndpoint(
                from: [missionControl],
                serviceName: "Mission"
            ) == nil
        )
    }

    @Test("Nameless discovery only selects a single instance")
    func namelessSelection() {
        #expect(TCPConnection.selectBonjourEndpoint(from: [missionControl], serviceName: nil) != nil)
        #expect(TCPConnection.selectBonjourEndpoint(from: [missionControl, swiftMCP], serviceName: nil) == nil)
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
