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

@Suite("Prompt Tests", .tags(.prompt, .unit))
struct PromptTests {
    
    @Suite("Metadata Tests")
    struct MetadataTests {
        
        @Test("Prompt metadata extraction identifies all prompts")
        func promptMetadataExtractionIdentifiesAllPrompts() throws {
            let server = PromptTestServer()
            let meta = server.mcpPromptMetadata
            #expect(meta.count == 3)
            #expect(meta.first { $0.name == "greet" } != nil)
            #expect(meta.first { $0.name == "setTaskPriority" } != nil)
            #expect(meta.first { $0.name == "pingPrompt" } != nil)
        }
    }

    @Suite("Completion Tests")
    struct CompletionTests {
        
        @Test("Prompt enum completion returns case labels")
        func promptEnumCompletionReturnsCaseLabels() async throws {
            let server = PromptTestServer()
            let request = JSONRPCMessage.request(
                id: 1,
                method: "completion/complete",
                params: [
                    "argument": ["name": "mood", "value": "h"],
                    "ref": ["type": "ref/prompt", "name": "greet"]
                ]
            )
            
            let message = try #require(await server.handleMessage(request))
            guard case .response(let response) = message else {
                throw TestError("Expected response")
            }
            
            let result = try #require(response.result)
            let comp = try #require(result["completion"]?.value as? [String: Any])
            let values = try #require(comp["values"] as? [String])
            #expect(values == ["happy", "sad", "excited"])
        }
    }
    
    @Suite("Capability Tests")
    struct CapabilityTests {
        
        @Test("Initialize shows prompts capability")
        func initializeShowsPromptsCapability() async throws {
            let server = PromptTestServer()
            let request = JSONRPCMessage.request(
                id: 1,
                method: "initialize",
                params: [:]
            )
            
            let message = try #require(await server.handleMessage(request))
            guard case .response(let response) = message else {
                throw TestError("Expected response")
            }
            
            let result = try #require(response.result)
            let caps = try #require(result["capabilities"]?.value as? [String: Any])
            #expect(caps["prompts"] != nil)
        }
    }
    
    @Suite("Prompt Execution Tests")
    struct PromptExecutionTests {
        
        @Test("Call prompts via mock client with parameters")
        func callPromptsViaMockClientWithParameters() async throws {
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
            
            let message = try #require(await client.send(request))
            guard case .response(let resp) = message else {
                throw TestError("Expected response")
            }
            
            let result = try #require(resp.result)
            let messages = try #require(result["messages"]?.value as? [[String: Any]])
            #expect(messages.count == 1)
            let content = try #require(messages.first?["content"] as? [String: Any])
            let text = try #require(content["text"] as? String)
            #expect(text.contains("excited"))
        }

        @Test("Call greet prompt with default mood")
        func callGreetPromptWithDefaultMood() async throws {
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
            
            let message = try #require(await client.send(request))
            guard case .response(let resp) = message else {
                throw TestError("Expected response")
            }
            
            let result = try #require(resp.result)
            let messages = try #require(result["messages"]?.value as? [[String: Any]])
            let content = try #require(messages.first?["content"] as? [String: Any])
            let text = try #require(content["text"] as? String)
            #expect(text.contains("happy"))
        }

        @Test("Call ping prompt returns expected response")
        func callPingPromptReturnsExpectedResponse() async throws {
            let server = PromptTestServer()
            let client = MockClient(server: server)
            let request = JSONRPCMessage.request(
                id: 1,
                method: "prompts/get",
                params: ["name": "pingPrompt"]
            )
            
            let message = try #require(await client.send(request))
            guard case .response(let resp) = message else {
                throw TestError("Expected response")
            }
            
            let result = try #require(resp.result)
            let messages = try #require(result["messages"]?.value as? [[String: Any]])
            let content = try #require(messages.first?["content"] as? [String: Any])
            let text = try #require(content["text"] as? String)
            #expect(text == "pong")
        }
    }

    @Suite("Advanced Completion Tests")
    struct AdvancedCompletionTests {
        
        @Test("Prompt enum completion with prefix returns matching items first")
        func promptEnumCompletionWithPrefixReturnsMatchingItemsFirst() async throws {
            let server = PromptTestServer()
            let request = JSONRPCMessage.request(
                id: 1,
                method: "completion/complete",
                params: [
                    "argument": ["name": "mood", "value": "s"],
                    "ref": ["type": "ref/prompt", "name": "greet"]
                ]
            )
            
            let message = try #require(await server.handleMessage(request))
            guard case .response(let response) = message else {
                throw TestError("Expected response")
            }
            
            let result = try #require(response.result)
            let comp = try #require(result["completion"]?.value as? [String: Any])
            let values = try #require(comp["values"] as? [String])
            
            // With prefix "s", "sad" should come first (matches prefix), then others
            #expect(values.first == "sad")
            #expect(values.contains("happy"))
            #expect(values.contains("excited"))
            #expect(values.count == 3)
        }

        @Test("Prompt enum completion with empty prefix returns all values")
        func promptEnumCompletionWithEmptyPrefixReturnsAllValues() async throws {
            let server = PromptTestServer()
            let request = JSONRPCMessage.request(
                id: 1,
                method: "completion/complete",
                params: [
                    "argument": ["name": "mood", "value": ""],
                    "ref": ["type": "ref/prompt", "name": "greet"]
                ]
            )
            
            let message = try #require(await server.handleMessage(request))
            guard case .response(let response) = message else {
                throw TestError("Expected response")
            }
            
            let result = try #require(response.result)
            let comp = try #require(result["completion"]?.value as? [String: Any])
            let values = try #require(comp["values"] as? [String])
            
            // With empty prefix, should return all values in original order
            #expect(values.count == 3)
            #expect(Set(values) == Set(["happy", "sad", "excited"]))
        }

        @Test("Prompt enum completion for integer-based enum")
        func promptEnumCompletionForIntegerBasedEnum() async throws {
            let server = PromptTestServer()
            let request = JSONRPCMessage.request(
                id: 1,
                method: "completion/complete",
                params: [
                    "argument": ["name": "priority", "value": "h"],
                    "ref": ["type": "ref/prompt", "name": "setTaskPriority"]
                ]
            )
            
            let message = try #require(await server.handleMessage(request))
            guard case .response(let response) = message else {
                throw TestError("Expected response")
            }
            
            let result = try #require(response.result)
            let comp = try #require(result["completion"]?.value as? [String: Any])
            let values = try #require(comp["values"] as? [String])
            
            // With prefix "h", "high" should come first (matches prefix), then others
            #expect(values.first == "high")
            #expect(values.contains("low"))
            #expect(values.contains("medium"))
            #expect(values.count == 3)
        }

        @Test("Prompt completion for non-existent prompt returns empty")
        func promptCompletionForNonExistentPromptReturnsEmpty() async throws {
            let server = PromptTestServer()
            let request = JSONRPCMessage.request(
                id: 1,
                method: "completion/complete",
                params: [
                    "argument": ["name": "mood", "value": "h"],
                    "ref": ["type": "ref/prompt", "name": "nonExistentPrompt"]
                ]
            )
            
            let message = try #require(await server.handleMessage(request))
            guard case .response(let response) = message else {
                throw TestError("Expected response")
            }
            
            let result = try #require(response.result)
            let comp = try #require(result["completion"]?.value as? [String: Any])
            let values = try #require(comp["values"] as? [String])
            
            // Should return empty array for non-existent prompt
            #expect(values.isEmpty)
        }
    }
}

// MARK: - Test Tags Extension
extension Tag {
    @Tag static var prompt: Self
}

@Suite("Additional Prompt Tests")
struct AdditionalPromptTests {
    
    @Test("Prompt completion for non-enum parameter returns empty")
    func promptCompletionForNonEnumParameterReturnsEmpty() async throws {
        let server = PromptTestServer()
        let request = JSONRPCMessage.request(
            id: 1,
            method: "completion/complete",
            params: [
                "argument": ["name": "name", "value": "Jo"],  // "name" is String, not enum
                "ref": ["type": "ref/prompt", "name": "greet"]
            ]
        )
        
        let message = try #require(await server.handleMessage(request))
        guard case .response(let response) = message else {
            throw TestError("Expected response")
        }
        
        let result = try #require(response.result)
        let comp = try #require(result["completion"]?.value as? [String: Any])
        let values = try #require(comp["values"] as? [String])
        
        // Should return empty array for non-enum parameter
        #expect(values.isEmpty)
    }

    @Test("Direct JSON encoding of PromptMessage")
    func directJSONEncodingOfPromptMessage() throws {
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
        let messagesValue = try #require(decoded["messages"]?.value as? [[String: Any]])
        let firstMessage = try #require(messagesValue.first)
        let content = try #require(firstMessage["content"] as? [String: Any])
        let text = try #require(content["text"] as? String)
        #expect(text == "Hello Oliver! Mood: excited")
    }
}
