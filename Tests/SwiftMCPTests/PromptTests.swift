import Foundation
import Testing
@testable import SwiftMCP

@MCPServer
class PromptTestServer {
    enum Mood: String, CaseIterable { case happy, sad, excited }

    @MCPPrompt(description: "Greets the user")
    func greet(name: String, mood: Mood = .happy) -> [PromptMessage] {
        [PromptMessage(role: .assistant, content: .init(text: "Hello \(name)! Mood: \(mood.rawValue)"))]
    }

    @MCPPrompt(description: "Ping")
    func pingPrompt() -> [PromptMessage] {
        [PromptMessage(role: .assistant, content: .init(text: "pong"))]
    }
}

@Test("Prompt metadata extraction")
func testPromptMetadata() throws {
    let server = PromptTestServer()
    let meta = server.mcpPromptMetadata
    #expect(meta.count == 2)
    #expect(meta.first { $0.name == "greet" } != nil)
    #expect(meta.first { $0.name == "pingPrompt" } != nil)
}

@Test("Prompt enum completion")
func testPromptEnumCompletion() async throws {
    let server = PromptTestServer()
    let request = JSONRPCMessage.request(
        id: 1,
        method: "completion/complete",
        params: [
            "argument": ["name": "mood", "value": "h"],
            "ref": ["type": "ref/prompt", "name": "greet"]
        ]
    )
    guard let message = await server.handleMessage(request), case .response(let response) = message else {
        #expect(Bool(false), "Expected response")
        return
    }
    let result = unwrap(response.result)
    let comp = unwrap(result["completion"]?.value as? [String: Any])
    let values = unwrap(comp["values"] as? [String])
    #expect(values == ["happy", "sad", "excited"])
}

@Test("Initialize shows prompts capability")
func testInitializeShowsPrompts() async throws {
    let server = PromptTestServer()
    let request = JSONRPCMessage.request(
        id: 1,
        method: "initialize",
        params: [:]
    )
    guard let message = await server.handleMessage(request), case .response(let response) = message else {
        #expect(Bool(false), "Expected response")
        return
    }
    let result = unwrap(response.result)
    let caps = unwrap(result["capabilities"]?.value as? [String: Any])
    #expect(caps["prompts"] != nil)
}

@Test("Call prompts via mock client")
func testPromptCallViaMockClient() async throws {
    let server = PromptTestServer()
    let client = MockClient(server: server)
    let request = JSONRPCMessage.request(
        id: 1,
        method: "prompts/get",
        params: [
            "name": "greet",
            "arguments": ["name": "Oliver", "mood": "excited"]
        ]
    )
    guard let message = await client.send(request), case .response(let resp) = message else {
        #expect(Bool(false), "Expected response")
        return
    }
    let result = unwrap(resp.result)
    let messages = unwrap(result["messages"]?.value as? [[String: Any]])
    #expect(messages.count == 1)
    let text = unwrap(messages.first?["content"] as? [String: Any])
    #expect((text["text"] as? String)?.contains("excited") == true)
}

@Test("Call greet prompt with default mood")
func testGreetPromptDefaultMood() async throws {
    let server = PromptTestServer()
    let client = MockClient(server: server)
    let request = JSONRPCMessage.request(
        id: 1,
        method: "prompts/get",
        params: [
            "name": "greet",
            "arguments": ["name": "Oliver"]
        ]
    )
    guard let message = await client.send(request), case .response(let resp) = message else {
        #expect(Bool(false), "Expected response")
        return
    }
    let result = unwrap(resp.result)
    let messages = unwrap(result["messages"]?.value as? [[String: Any]])
    let text = unwrap(messages.first?["content"] as? [String: Any])
    #expect((text["text"] as? String)?.contains("happy") == true)
}

@Test("Call ping prompt")
func testPingPromptViaMockClient() async throws {
    let server = PromptTestServer()
    let client = MockClient(server: server)
    let request = JSONRPCMessage.request(
        id: 1,
        method: "prompts/get",
        params: ["name": "pingPrompt"]
    )
    guard let message = await client.send(request), case .response(let resp) = message else {
        #expect(Bool(false), "Expected response")
        return
    }
    let result = unwrap(resp.result)
    let messages = unwrap(result["messages"]?.value as? [[String: Any]])
    let text = unwrap(messages.first?["content"] as? [String: Any])
    #expect(text["text"] as? String == "pong")
}
