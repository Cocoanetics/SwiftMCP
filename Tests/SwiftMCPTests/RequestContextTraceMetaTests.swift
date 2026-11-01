import Testing
@testable import SwiftMCP

@Suite("RequestContext OTel _meta")
struct RequestContextTraceMetaTests {
    private let traceparent = "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"

    private func makeContext(meta: JSONDictionary) -> RequestContext {
        RequestContext(message: .request(id: 1, method: "tools/call", params: .object(["_meta": .object(meta)])))
    }

    @Test("All three keys round-trip")
    func allKeys() {
        let context = makeContext(meta: [
            "traceparent": .string(traceparent),
            "tracestate": .string("congo=t61rcWkgMzE"),
            "baggage": .string("userId=alice,serverNode=DF28"),
            "progressToken": .string("p1")
        ])
        #expect(context.meta?.traceparent == traceparent)
        #expect(context.meta?.tracestate == "congo=t61rcWkgMzE")
        #expect(context.meta?.baggage == "userId=alice,serverNode=DF28")
        #expect(context.meta?.progressToken == .string("p1"))
    }

    @Test("Single key leaves others nil")
    func singleKey() {
        let context = makeContext(meta: ["traceparent": .string(traceparent)])
        #expect(context.meta?.traceparent == traceparent)
        #expect(context.meta?.tracestate == nil)
        #expect(context.meta?.baggage == nil)
    }

    @Test("Non-string values are absent")
    func nonStrings() {
        let context = makeContext(meta: [
            "traceparent": .object([:]),
            "tracestate": .string("a=b"),
            "baggage": .integer(5)
        ])
        #expect(context.meta?.traceparent == nil)
        #expect(context.meta?.tracestate == "a=b")
        #expect(context.meta?.baggage == nil)
    }

    @Test("Prefixed keys are not read")
    func prefixed() {
        let context = makeContext(meta: ["io.modelcontextprotocol/traceparent": .string(traceparent)])
        #expect(context.meta?.traceparent == nil)
    }

    @Test("Notification _meta is parsed")
    func notification() {
        let message = JSONRPCMessage.notification(
            method: "notifications/cancelled",
            params: .object(["_meta": .object(["traceparent": .string(traceparent)])])
        )
        #expect(RequestContext(message: message).meta?.traceparent == traceparent)
    }
}
