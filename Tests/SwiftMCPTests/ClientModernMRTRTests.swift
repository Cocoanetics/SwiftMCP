#if Client
import Testing
import Foundation
@testable import SwiftMCP

@Suite("Modern client MRTR retries")
struct ClientModernMRTRTests {
    private func mrtrServer() -> FakeLineServer {
        makeModernServer { request in
            let params = request.params
            func input(_ ids: [String], state: String) -> JSONRPCMessage {
                var requests: JSONDictionary = [:]
                for id in ids {
                    requests[id] = .object(["method": .string("elicitation/create"), "params": .object([:])])
                }
                return FakeLineServer.ok(request, [
                    "resultType": .string("input_required"),
                    "inputRequests": .object(requests),
                    "requestState": .string(state)
                ])
            }
            let responses = params?["inputResponses"]?.dictionaryValue ?? [:]
            switch (request.method, params?["requestState"]?.stringValue) {
            case (_, nil):
                return input(["a"], state: "s1 opaque/==")
            case (_, "s1 opaque/=="):
                return responses["a"] != nil ? input(["b", "c"], state: "s2") : FakeLineServer.fail(request, -32602)
            default:
                guard ["a", "b", "c"].allSatisfy({ responses[$0] != nil }) else {
                    return FakeLineServer.fail(request, -32602)
                }
                switch request.method {
                case "resources/read":
                    return FakeLineServer.ok(request, ["contents": .array([.object([
                        "uri": .string("file:///a"), "text": .string("body")
                    ])])])
                case "prompts/get":
                    return FakeLineServer.ok(request, ["messages": .array([.object([
                        "role": .string("user"),
                        "content": .object(["type": .string("text"), "text": .string("p")])
                    ])])])
                default:
                    return FakeLineServer.ok(request, ["content": .array([
                        .object(["type": .string("text"), "text": .string("done")])
                    ])])
                }
            }
        }
    }

    @Test("tools/call completes three rounds with new ids, verbatim state and cumulative responses")
    func multiRoundToolCall() async throws {
        let fake = mrtrServer()
        let proxy = await makeModernProxy(fake, preference: .modern)
        await proxy.setInputHandler(EchoInputHandler())
        try await proxy.establishConnection(clientName: "t", clientVersion: "1")

        #expect(try await proxy.callTool("greet") == "done")

        let calls = fake.requests("tools/call")
        #expect(calls.count == 3)
        #expect(Set(calls.map(\.id)).count == 3)
        #expect(calls.map { $0.params?["requestState"]?.stringValue } == [nil, "s1 opaque/==", "s2"])
        let second = try #require(calls[1].params?["inputResponses"]?.dictionaryValue)
        #expect(Set(second.keys) == ["a"])
        let third = try #require(calls[2].params?["inputResponses"]?.dictionaryValue)
        #expect(Set(third.keys) == ["a", "b", "c"])
        #expect(third["b"]?["content"]?["method"]?.stringValue == "elicitation/create")
        for call in calls {
            #expect(call.params?["name"]?.stringValue == "greet")
            #expect(call.params?["_meta"]?[MCPMetaKey.clientCapabilities]?["elicitation"] != nil)
        }
        await proxy.disconnect()
    }

    @Test("resources/read and prompts/get retry on input_required")
    func readAndPromptRounds() async throws {
        let fake = mrtrServer()
        let proxy = await makeModernProxy(fake, preference: .modern)
        await proxy.setInputHandler(EchoInputHandler())
        try await proxy.establishConnection(clientName: "t", clientVersion: "1")

        let contents = try await proxy.readResource(uri: try #require(URL(string: "file:///a")))
        #expect(contents.count == 1)
        #expect(fake.requests("resources/read").count == 3)

        _ = try await proxy.getPrompt(name: "p")
        #expect(fake.requests("prompts/get").count == 3)
        await proxy.disconnect()
    }

    @Test("A missing handler or unsupported input method fails instead of retrying partially")
    func unsupportedInput() async throws {
        let fake = mrtrServer()
        let proxy = await makeModernProxy(fake, preference: .modern)
        try await proxy.establishConnection(clientName: "t", clientVersion: "1")
        await #expect(throws: MCPServerProxyError.self) { try await proxy.callTool("greet") }
        #expect(fake.requests("tools/call").count == 1)

        struct RootsOnly: MCPClientInputHandler {
            var supportedMethods: Set<String> { ["roots/list"] }
            func handleInput(method: String, params: JSONValue?) async throws -> JSONValue { .object([:]) }
        }
        await proxy.setInputHandler(RootsOnly())
        await #expect(throws: MCPServerProxyError.self) { try await proxy.callTool("greet") }
        await proxy.disconnect()
    }

    @Test("The round cap stops a server that never completes")
    func roundCap() async throws {
        let fake = makeModernServer { request in
            FakeLineServer.ok(request, [
                "resultType": .string("input_required"),
                "inputRequests": .object([:]),
                "requestState": .string("again")
            ])
        }
        let proxy = await makeModernProxy(fake, preference: .modern)
        await proxy.setMaxInputRounds(3)
        try await proxy.establishConnection(clientName: "t", clientVersion: "1")
        await #expect(throws: MCPServerProxyError.self) { try await proxy.callTool("loop") }
        #expect(fake.requests("tools/call").count == 4)
        await proxy.disconnect()
    }

    @Test("input_required with neither inputRequests nor requestState is rejected")
    func emptyInputRequired() async throws {
        let fake = makeModernServer { request in
            FakeLineServer.ok(request, ["resultType": .string("input_required")])
        }
        let proxy = await makeModernProxy(fake, preference: .modern)
        try await proxy.establishConnection(clientName: "t", clientVersion: "1")
        await #expect(throws: MCPServerProxyError.self) { try await proxy.callTool("x") }
        await proxy.disconnect()
    }
}
#endif
