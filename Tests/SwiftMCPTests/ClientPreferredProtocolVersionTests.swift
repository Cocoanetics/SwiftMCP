#if Client
import Testing
import Foundation
@testable import SwiftMCP

/// `MCPServerProxy.preferredProtocolVersion`: which revision `connect()` proposes,
/// and how it combines with `eraPreference`.
@Suite("Client preferred protocol version")
struct ClientPreferredProtocolVersionTests {

    /// A legacy server that echoes the proposed revision when it supports it,
    /// otherwise answers with `answer` (down-negotiation), and offers `discover`
    /// only when `discoverVersions` is set.
    private func makeLegacyServer(
        answer: String = MCPProtocolVersion.latest,
        discoverVersions: [String]? = nil
    ) -> FakeLineServer {
        FakeLineServer { message in
            guard case .request(let request) = message else { return nil }
            switch request.method {
            case "initialize":
                let proposed = request.params?["protocolVersion"]?.stringValue ?? answer
                var result = FakeLineServer.initializeResult
                result["protocolVersion"] = .string(
                    MCPProtocolVersion.legacySupported.contains(proposed) && proposed <= answer ? proposed : answer
                )
                return FakeLineServer.ok(request, result)
            case "server/discover":
                guard let discoverVersions else { return FakeLineServer.fail(request, -32601) }
                return FakeLineServer.ok(request, FakeLineServer.discoverResult(discoverVersions))
            case "ping":
                return FakeLineServer.ok(request, [:])
            default:
                return FakeLineServer.fail(request, -32601)
            }
        }
    }

    private func proposedVersion(_ fake: FakeLineServer) -> String? {
        fake.requests("initialize").first?.params?["protocolVersion"]?.stringValue
    }

    @Test("Without a preference, initialize proposes the newest legacy revision")
    func defaultProposesLatest() async throws {
        let fake = makeLegacyServer()
        let proxy = await makeModernProxy(fake, preference: .legacy)
        #expect(await proxy.preferredProtocolVersion == nil)
        try await proxy.establishConnection(clientName: "t", clientVersion: "1")
        #expect(proposedVersion(fake) == MCPProtocolVersion.latest)
        #expect(await proxy.negotiatedProtocolVersion == MCPProtocolVersion.latest)
        await proxy.disconnect()
    }

    @Test(
        "A preferred legacy revision is proposed without a discover probe",
        arguments: ["2025-03-26", "2025-06-18", "2025-11-25"]
    )
    func preferredLegacySkipsProbe(version: String) async throws {
        let fake = makeLegacyServer(discoverVersions: [MCPProtocolVersion.modern, MCPProtocolVersion.latest])
        let proxy = await makeModernProxy(fake, preference: .auto)
        await proxy.setPreferredProtocolVersion(version)
        try await proxy.establishConnection(clientName: "t", clientVersion: "1")

        #expect(fake.requests("server/discover").isEmpty)
        #expect(proposedVersion(fake) == version)
        #expect(await proxy.negotiatedEra == .legacy)
        #expect(await proxy.negotiatedProtocolVersion == version)
        await proxy.disconnect()
    }

    @Test("The server may answer an older revision than the one preferred")
    func serverDownNegotiates() async throws {
        let fake = makeLegacyServer(answer: "2025-06-18")
        let proxy = await makeModernProxy(fake, preference: .legacy)
        await proxy.setPreferredProtocolVersion("2025-11-25")
        try await proxy.establishConnection(clientName: "t", clientVersion: "1")

        #expect(proposedVersion(fake) == "2025-11-25")
        #expect(await proxy.negotiatedProtocolVersion == "2025-06-18")
        await proxy.disconnect()
    }

    @Test("A preferred modern revision is selected from discover")
    func preferredModernSelected() async throws {
        let fake = makeModernServer()
        let proxy = await makeModernProxy(fake, preference: .auto)
        await proxy.setPreferredProtocolVersion(MCPProtocolVersion.modern)
        try await proxy.establishConnection(clientName: "t", clientVersion: "1")

        #expect(await proxy.negotiatedEra == .modern)
        #expect(await proxy.modernProtocolVersion == MCPProtocolVersion.modern)
        #expect(fake.requests("initialize").isEmpty)
        await proxy.disconnect()
    }

    @Test("Auto with a preferred modern revision falls back when the server lacks it")
    func preferredModernFallsBack() async throws {
        let fake = makeLegacyServer(discoverVersions: [MCPProtocolVersion.latest])
        let proxy = await makeModernProxy(fake, preference: .auto)
        await proxy.setPreferredProtocolVersion(MCPProtocolVersion.modern)
        try await proxy.establishConnection(clientName: "t", clientVersion: "1")

        #expect(await proxy.negotiatedEra == .legacy)
        // `initialize` never negotiates a modern revision, so it proposes the newest legacy one.
        #expect(proposedVersion(fake) == MCPProtocolVersion.latest)
        await proxy.disconnect()
    }

    @Test("Modern with a preferred modern revision the server lacks fails")
    func preferredModernStrict() async throws {
        let fake = makeLegacyServer(discoverVersions: [MCPProtocolVersion.latest])
        let proxy = await makeModernProxy(fake, preference: .modern)
        await proxy.setPreferredProtocolVersion(MCPProtocolVersion.modern)
        await #expect(throws: MCPServerProxyError.self) {
            try await proxy.establishConnection(clientName: "t", clientVersion: "1")
        }
        #expect(fake.requests("initialize").isEmpty)
        await proxy.disconnect()
    }

    struct ConflictCase: Sendable, CustomTestStringConvertible {
        let version: String
        let preference: MCPClientEraPreference
        var testDescription: String { "\(version) with .\(preference.rawValue)" }
    }

    @Test(
        "A preference contradicting eraPreference fails before sending anything",
        arguments: [
            ConflictCase(version: "2025-06-18", preference: .modern),
            ConflictCase(version: MCPProtocolVersion.modern, preference: .legacy)
        ]
    )
    func conflictingPreferenceThrows(_ testCase: ConflictCase) async throws {
        let fake = makeLegacyServer(discoverVersions: [MCPProtocolVersion.modern, MCPProtocolVersion.latest])
        let proxy = await makeModernProxy(fake, preference: testCase.preference)
        await proxy.setPreferredProtocolVersion(testCase.version)
        do {
            try await proxy.establishConnection(clientName: "t", clientVersion: "1")
            Issue.record("expected the contradiction to throw")
        } catch MCPServerProxyError.communicationError(let message) {
            #expect(message.contains("contradicts"))
        }
        #expect(fake.received.isEmpty)
        await proxy.disconnect()
    }

    @Test("Before negotiation the HTTP version header follows the preferred revision")
    func headerFollowsPreference() async throws {
        let url = try #require(URL(string: "http://127.0.0.1:1/mcp"))
        let proxy = MCPServerProxy(config: .sse(config: MCPServerSseConfig(url: url)))
        #expect(await proxy.mcpProtocolVersionHeaderValue == MCPProtocolVersion.latest)
        await proxy.setPreferredProtocolVersion("2025-06-18")
        #expect(await proxy.mcpProtocolVersionHeaderValue == "2025-06-18")
        // 2025-03-26 predates the header.
        await proxy.setPreferredProtocolVersion("2025-03-26")
        #expect(await proxy.mcpProtocolVersionHeaderValue == nil)
        // A modern preference does not change the legacy handshake's header.
        await proxy.setPreferredProtocolVersion(MCPProtocolVersion.modern)
        #expect(await proxy.mcpProtocolVersionHeaderValue == MCPProtocolVersion.latest)
    }
}
#endif
