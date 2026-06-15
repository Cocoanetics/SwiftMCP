import Foundation
import Testing
@testable import SwiftMCP

@Suite("JSON-RPC batching gate")
struct JSONRPCBatchingGateTests {

    private func data(_ string: String) -> Data { Data(string.utf8) }

    @Test("isBatchPayload detects top-level arrays, ignoring leading whitespace")
    func detectsArrays() {
        #expect(JSONRPCMessage.isBatchPayload(data("[]")))
        #expect(JSONRPCMessage.isBatchPayload(data(#"[{"jsonrpc":"2.0"}]"#)))
        #expect(JSONRPCMessage.isBatchPayload(data("  \n\t [1, 2]")))
    }

    @Test("isBatchPayload rejects single objects and empty payloads")
    func rejectsNonArrays() {
        #expect(JSONRPCMessage.isBatchPayload(data("{}")) == false)
        #expect(JSONRPCMessage.isBatchPayload(data(#"  {"a":1}"#)) == false)
        #expect(JSONRPCMessage.isBatchPayload(data("")) == false)
        #expect(JSONRPCMessage.isBatchPayload(data("   ")) == false)
    }

    @Test("Batches are rejected only on revisions that removed batching")
    func gateByVersion() {
        let batch = data(#"[{"jsonrpc":"2.0","method":"ping","id":1}]"#)
        #expect(JSONRPCMessage.batchingRejected(body: batch, version: "2025-03-26") == false) // batching present
        #expect(JSONRPCMessage.batchingRejected(body: batch, version: "2025-06-18") == true)  // removed here
        #expect(JSONRPCMessage.batchingRejected(body: batch, version: "2025-11-25") == true)
        #expect(JSONRPCMessage.batchingRejected(body: batch, version: "2026-07-28") == true)
    }

    @Test("Single messages are never rejected")
    func singleNeverRejected() {
        let single = data(#"{"jsonrpc":"2.0","method":"ping","id":1}"#)
        for version in ["2025-03-26", "2025-06-18", "2025-11-25", "2026-07-28"] {
            #expect(JSONRPCMessage.batchingRejected(body: single, version: version) == false)
        }
    }

    @Test("Unknown / not-yet-negotiated versions are treated permissively")
    func unknownVersionAllowed() {
        let batch = data(#"[{"jsonrpc":"2.0","method":"ping","id":1}]"#)
        #expect(JSONRPCMessage.batchingRejected(body: batch, version: "1999-01-01") == false)
    }

    @Test("initializeProtocolVersion reads a leading initialize's declared version")
    func initializeVersionExtraction() {
        let initialize = JSONRPCMessage.request(
            id: 1, method: "initialize", params: ["protocolVersion": .string("2025-11-25")]
        )
        let ping = JSONRPCMessage.request(id: 2, method: "ping")

        #expect(SessionInitializationGate.initializeProtocolVersion([initialize, ping]) == "2025-11-25")
        #expect(SessionInitializationGate.initializeProtocolVersion([ping, initialize]) == nil)   // not leading
        #expect(SessionInitializationGate.initializeProtocolVersion([ping]) == nil)

        let bareInitialize = JSONRPCMessage.request(id: 1, method: "initialize", params: [:])
        #expect(SessionInitializationGate.initializeProtocolVersion([bareInitialize]) == nil)
    }

    @Test("batchingVersion prefers the negotiated session, then a leading initialize, then latest")
    func batchingVersionResolution() async {
        let ping = JSONRPCMessage.request(id: 1, method: "ping")

        let negotiated = Session(id: UUID())
        await negotiated.setNegotiatedProtocolVersion("2025-06-18")
        #expect(await JSONRPCMessage.batchingVersion(for: [ping], session: negotiated) == "2025-06-18")

        let fresh = Session(id: UUID())
        let initialize = JSONRPCMessage.request(
            id: 1, method: "initialize", params: ["protocolVersion": .string("2025-03-26")]
        )
        #expect(await JSONRPCMessage.batchingVersion(for: [initialize, ping], session: fresh) == "2025-03-26")
        #expect(await JSONRPCMessage.batchingVersion(for: [ping], session: fresh) == MCPProtocolVersion.latest)
    }

    @Test("batchingRejectionResponse is a JSON-RPC -32600 error with no id")
    func rejectionResponseShape() {
        guard case .errorResponse(let data) = JSONRPCMessage.batchingRejectionResponse(version: "2025-11-25") else {
            Issue.record("Expected an error response")
            return
        }
        #expect(data.id == nil)
        #expect(data.error.code == -32600)
    }
}
