import Foundation
import Testing
import AnyCodable
@testable import SwiftMCP

@MCPServer
class PromptTestServer {
    enum Mood: String, CaseIterable { case happy, sad, excited }
    enum Priority: Int, CaseIterable { case low = 1, medium = 2, high = 3 }

    @MCPPrompt(description: "Greets the user")
    func greet(name: String, mood: Mood = .happy) -> [PromptMessage] {
        [PromptMessage(role: .assistant, content: .init(text: "Hello \(name)! Mood: \(mood.rawValue)"))]
    }

    @MCPPrompt(description: "Sets task priority")
    func setTaskPriority(task: String, priority: Priority = .medium) -> [PromptMessage] {
        [PromptMessage(role: .assistant, content: .init(text: "Task '\(task)' set to priority \(priority.rawValue)"))]
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
    #expect(meta.count == 3)
    #expect(meta.first { $0.name == "greet" } != nil)
    #expect(meta.first { $0.name == "setTaskPriority" } != nil)
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
    let content = unwrap(messages.first?["content"] as? [String: Any])
    let text = unwrap(content["text"] as? String)
    #expect(text.contains("excited"))
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
    let content = unwrap(messages.first?["content"] as? [String: Any])
    let text = unwrap(content["text"] as? String)
    #expect(text.contains("happy"))
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
    let content = unwrap(messages.first?["content"] as? [String: Any])
    let text = unwrap(content["text"] as? String)
    #expect(text == "pong")
}

@Test("Prompt enum completion with prefix returns matching items first")
func testPromptEnumCompletionWithPrefix() async throws {
    let server = PromptTestServer()
    let request = JSONRPCMessage.request(
        id: 1,
        method: "completion/complete",
        params: [
            "argument": ["name": "mood", "value": "s"],
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
    
    // With prefix "s", "sad" should come first (matches prefix), then others
    #expect(values.first == "sad")
    #expect(values.contains("happy"))
    #expect(values.contains("excited"))
    #expect(values.count == 3)
}

@Test("Prompt enum completion with empty prefix returns all values")
func testPromptEnumCompletionEmptyPrefix() async throws {
    let server = PromptTestServer()
    let request = JSONRPCMessage.request(
        id: 1,
        method: "completion/complete",
        params: [
            "argument": ["name": "mood", "value": ""],
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
    
    // With empty prefix, should return all values in original order
    #expect(values.count == 3)
    #expect(Set(values) == Set(["happy", "sad", "excited"]))
}

@Test("Prompt enum completion for integer-based enum")
func testPromptIntegerEnumCompletion() async throws {
    let server = PromptTestServer()
    let request = JSONRPCMessage.request(
        id: 1,
        method: "completion/complete",
        params: [
            "argument": ["name": "priority", "value": "h"],
            "ref": ["type": "ref/prompt", "name": "setTaskPriority"]
        ]
    )
    guard let message = await server.handleMessage(request), case .response(let response) = message else {
        #expect(Bool(false), "Expected response")
        return
    }
    let result = unwrap(response.result)
    let comp = unwrap(result["completion"]?.value as? [String: Any])
    let values = unwrap(comp["values"] as? [String])
    
    // With prefix "h", "high" should come first (matches prefix), then others
    #expect(values.first == "high")
    #expect(values.contains("low"))
    #expect(values.contains("medium"))
    #expect(values.count == 3)
}

@Test("Prompt completion for non-existent prompt returns empty")
func testPromptCompletionNonExistentPrompt() async throws {
    let server = PromptTestServer()
    let request = JSONRPCMessage.request(
        id: 1,
        method: "completion/complete",
        params: [
            "argument": ["name": "mood", "value": "h"],
            "ref": ["type": "ref/prompt", "name": "nonExistentPrompt"]
        ]
    )
    guard let message = await server.handleMessage(request), case .response(let response) = message else {
        #expect(Bool(false), "Expected response")
        return
    }
    let result = unwrap(response.result)
    let comp = unwrap(result["completion"]?.value as? [String: Any])
    let values = unwrap(comp["values"] as? [String])
    
    // Should return empty array for non-existent prompt
    #expect(values.isEmpty)
}

@Test("Prompt completion for non-enum parameter returns empty")
func testPromptCompletionNonEnumParameter() async throws {
    let server = PromptTestServer()
    let request = JSONRPCMessage.request(
        id: 1,
        method: "completion/complete",
        params: [
            "argument": ["name": "name", "value": "Jo"],  // "name" is String, not enum
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
    
    // Should return empty array for non-enum parameter
    #expect(values.isEmpty)
}

@Test("Direct JSON encoding of PromptMessage")
func testPromptMessageJSONEncoding() throws {
    // Create a PromptMessage array like the server would
    let messages = [PromptMessage(role: .assistant, content: .init(text: "Hello Oliver! Mood: excited"))]
    
    // Encode as JSON like it would go over the wire
    let response = ["description": "greet", "messages": AnyCodable(messages)]
    let encoder = JSONEncoder()
    let jsonData = try encoder.encode(response)
    
    // Decode back like a client would
    let decoder = JSONDecoder()
    let decoded = try decoder.decode([String: AnyCodable].self, from: jsonData)
    
    // Now test if we can access it like the test expects
    if let messagesValue = decoded["messages"]?.value as? [[String: Any]] {
        if let firstMessage = messagesValue.first {
            if let content = firstMessage["content"] as? [String: Any] {
                #expect(content["text"] as? String == "Hello Oliver! Mood: excited")
            }
        }
    }
}
