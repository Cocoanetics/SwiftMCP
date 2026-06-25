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

    @Test("A decoupled TCP transport derives its service type from the name")
    func tcpServerless() {
        let transport = TCPBonjourTransport(serviceName: "acpx")
        #expect(transport.server == nil)
        #expect(transport.serviceName == "acpx")
        #expect(transport.serviceType == TCPBonjourTransport.serviceType(for: "acpx"))
        let _: any MCPTransport = transport
    }
}
#endif
