#if Client
import Testing
@testable import SwiftMCP

/// The client must echo the *negotiated* protocol revision in the
/// `MCP-Protocol-Version` header — and omit the header entirely for revisions
/// that predate it (it is a 2025-06-18 feature). This mirrors the server's
/// `validateHTTPProtocolVersion`, which rejects a header disagreeing with the
/// negotiated session version, so echoing a stale `latest` would break a
/// down-negotiated connection.
@Suite("Client MCP-Protocol-Version header")
struct ClientProtocolVersionHeaderTests {

    @Test(
        "Revisions that define the header echo their own version",
        arguments: ["2025-06-18", "2025-11-25"]
    )
    func sendsHeaderForHeaderCarryingRevisions(_ version: String) {
        #expect(MCPServerProxy.mcpProtocolVersionHeader(for: version) == version)
    }

    @Test("2025-03-26 predates the header, so it is omitted")
    func omitsHeaderForPre0618() {
        #expect(MCPServerProxy.mcpProtocolVersionHeader(for: "2025-03-26") == nil)
    }

    @Test("The proposed latest carries the header (the pre-negotiation default)")
    func latestSendsHeader() {
        #expect(
            MCPServerProxy.mcpProtocolVersionHeader(for: MCPProtocolVersion.latest)
                == MCPProtocolVersion.latest
        )
    }

    @Test("An unknown revision is treated permissively (sent as-is)")
    func unknownRevisionSentAsIs() {
        #expect(MCPServerProxy.mcpProtocolVersionHeader(for: "2099-01-01") == "2099-01-01")
    }
}
#endif
