import Foundation
import Testing
@testable import SwiftMCP

/// The `initialize` handshake must follow the MCP lifecycle negotiation rules:
/// echo a supported revision, otherwise respond with the server's latest
/// supported revision rather than rejecting the handshake (so a client that
/// proposes a newer revision can still connect at the highest the server
/// offers).
@Suite("Initialize protocol-version negotiation")
struct InitializeNegotiationTests {

    private func negotiatedVersion(proposing version: String?) async throws -> String {
        var params: JSONDictionary = [
            "capabilities": .object([:]),
            "clientInfo": .object(["name": .string("TestClient"), "version": .string("1.0")])
        ]
        if let version {
            params["protocolVersion"] = .string(version)
        }
        let request = JSONRPCMessage.request(id: 1, method: "initialize", params: params)

        let message = try #require(await Calculator().handleMessage(request))
        guard case .response(let response) = message else {
            throw TestError("expected a success response, got \(message)")
        }
        let result = try #require(response.result)
        return try #require(result["protocolVersion"]?.stringValue)
    }

    @Test("A supported revision is echoed back unchanged", arguments: ["2025-03-26", "2025-06-18", "2025-11-25"])
    func echoesSupportedRevision(_ version: String) async throws {
        let negotiated = try await negotiatedVersion(proposing: version)
        #expect(negotiated == version)
    }

    @Test("A newer/unsupported revision down-negotiates to the server's latest")
    func downNegotiatesUnsupportedRevision() async throws {
        // A revision the server doesn't know (e.g. a future modern one) must not
        // fail the handshake — the server offers its latest instead.
        let negotiated = try await negotiatedVersion(proposing: "2099-01-01")
        #expect(negotiated == MCPProtocolVersion.latest)

        let modern = try await negotiatedVersion(proposing: MCPProtocolVersion.modern)
        #expect(modern == MCPProtocolVersion.latest)
    }

    @Test("An absent protocolVersion assumes the server's latest")
    func absentRevisionAssumesLatest() async throws {
        let negotiated = try await negotiatedVersion(proposing: nil)
        #expect(negotiated == MCPProtocolVersion.latest)
    }
}
