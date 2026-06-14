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
}
