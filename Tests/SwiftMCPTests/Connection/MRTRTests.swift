#if Server
import Testing
import Foundation
import HTTPTypes
@testable import SwiftMCP

@Suite("MRTR (input_required round trips)")
struct MRTRTests {

    // MARK: - Model

    @Test("InputRequiredResult round-trips in the spec shape")
    func modelRoundTrip() throws {
        let result = InputRequiredResult(
            inputRequests: ["input-0": InputRequest(method: "elicitation/create", params: .object([:]))],
            requestState: "opaque"
        )
        let decoded = try JSONDecoder().decode(
            InputRequiredResult.self, from: try JSONEncoder().encode(result)
        )
        #expect(decoded.resultType == "input_required")
        #expect(decoded.inputRequests?["input-0"]?.method == "elicitation/create")
        #expect(decoded.requestState == "opaque")
    }

    // MARK: - Round trips

    @Test("Single elicit: input_required, then retry completes with the answer")
    func singleRoundTrip() async throws {
        let transport = HTTPSSETransport(server: MRTRTestServer())
        let adapter = InMemoryHTTPServerAdapter(engine: transport)

        let first = try await mrtrSend(adapter, headers: mrtrCallHeaders(tool: "askName"),
                                   body: mrtrCallBody(tool: "askName"))
        #expect(first["resultType"]?.stringValue == "input_required")
        let requests = try #require(first["inputRequests"]?.dictionaryValue)
        let input0 = try #require(requests["input-0"]?.dictionaryValue)
        #expect(input0["method"]?.stringValue == "elicitation/create")
        let state = try #require(first["requestState"]?.stringValue)

        let retry = try await mrtrSend(adapter, headers: mrtrCallHeaders(tool: "askName"), body: mrtrCallBody(
            tool: "askName",
            extraParams: [
                "inputResponses": .object(["input-0": mrtrAcceptResponse(["name": .string("Oliver")])]),
                "requestState": .string(state)
            ]
        ))
        let content = retry["content"]?.arrayValue?.first?.dictionaryValue
        #expect(content?["text"]?.stringValue == "Hello Oliver")
    }

    @Test("Two elicits: the accumulator carries round-1 answers through round 2")
    func multiRoundTrip() async throws {
        let transport = HTTPSSETransport(server: MRTRTestServer())
        let adapter = InMemoryHTTPServerAdapter(engine: transport)

        let round1 = try await mrtrSend(adapter, headers: mrtrCallHeaders(tool: "askTwo"),
                                    body: mrtrCallBody(tool: "askTwo"))
        #expect(round1["resultType"]?.stringValue == "input_required")
        #expect(round1["inputRequests"]?.dictionaryValue?["input-0"] != nil)
        let state1 = try #require(round1["requestState"]?.stringValue)

        let round2 = try await mrtrSend(adapter, headers: mrtrCallHeaders(tool: "askTwo"), body: mrtrCallBody(
            tool: "askTwo",
            extraParams: [
                "inputResponses": .object(["input-0": mrtrAcceptResponse(["a": .string("one")])]),
                "requestState": .string(state1)
            ]
        ))
        #expect(round2["resultType"]?.stringValue == "input_required")
        #expect(round2["inputRequests"]?.dictionaryValue?["input-1"] != nil)
        let state2 = try #require(round2["requestState"]?.stringValue)

        // Round 3 carries only input-1's answer; input-0 rides in the signed state.
        let final = try await mrtrSend(adapter, headers: mrtrCallHeaders(tool: "askTwo"), body: mrtrCallBody(
            tool: "askTwo",
            extraParams: [
                "inputResponses": .object(["input-1": mrtrAcceptResponse(["b": .string("two")])]),
                "requestState": .string(state2)
            ]
        ))
        let content = final["content"]?.arrayValue?.first?.dictionaryValue
        #expect(content?["text"]?.stringValue == "one+two")
    }

}
#endif
