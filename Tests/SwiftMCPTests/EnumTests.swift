import Testing
import AnyCodable
@testable import SwiftMCP

// MARK: - Test Enums

// Enum with integer raw values
enum Priority: Int, CaseIterable {
    case low = 0
    case medium = 1
    case high = 2
}

// Enum with string raw values
enum Status: String, CaseIterable {
    case pending = "PENDING"
    case active = "ACTIVE"
    case completed = "COMPLETED"
}

// Enum with custom string representation
enum SortOrder: String, CaseIterable, CustomStringConvertible {
    case ascending = "ascending"
    case descending = "descending"
    
	var description: String {
        switch self {
        case .ascending: return "SORT_ASC"
        case .descending: return "SORT_DESC"
        }
    }
}

// MARK: - Test Server

@MCPServer
class EnumTestServer {
    /// Process a priority value
    /// - Parameter priority: The priority to process
    @MCPTool
    func processPriority(priority: Priority) -> String {
        return "Priority: \(priority.rawValue)"
    }
    
    /// Process a status value
    /// - Parameter status: The status to process
    @MCPTool
    func processStatus(status: Status) -> String {
        return "Status: \(status.rawValue)"
    }
    
    /// Process a sort order
    /// - Parameter order: The sort order to process
    @MCPTool
    func processSortOrder(order: SortOrder) -> String {
        return "Order: \(order)"
    }
    
    /// Process an array of priorities
    /// - Parameter priorities: Array of priorities to process
    @MCPTool
    func processPriorities(priorities: [Priority]) -> String {
        return priorities.map { "\($0.rawValue)" }.joined(separator: ",")
    }
    
    /// Process an optional array of statuses
    /// - Parameter statuses: Optional array of statuses to process
    @MCPTool
    func processOptionalStatuses(statuses: [Status]? = nil) -> String {
        return statuses?.map { $0.rawValue }.joined(separator: ",") ?? "empty"
    }
}

// MARK: - Tests

@Suite("Enum Processing Tests", .tags(.enumType, .unit))
struct EnumTests {
    
    @Suite("Raw Value Enum Processing")
    struct RawValueTests {
        
        @Test("Integer raw value enum processing returns correct value")
        func integerRawValueEnumProcessing() async throws {
            let server = EnumTestServer()
            let client = MockClient(server: server)
            
            let request = JSONRPCMessage.request(
                id: 1,
                method: "tools/call",
                params: [
                    "name": "processPriority",
                    "arguments": ["priority": "high"]
                ]
            )
            
            let response = await client.send(request)
            guard case .response(let responseData) = response else {
                throw TestError("Expected response case")
            }
            
            #expect(responseData.id == .int(1))
            let result = try #require(responseData.result)
            let isError = try #require(result["isError"]?.value as? Bool)
            #expect(isError == false)
            let content = try #require(result["content"]?.value as? [[String: String]])
            let firstContent = try #require(content.first)
            let type = try #require(firstContent["type"])
            let text = try #require(firstContent["text"])
            #expect(type == "text")
            #expect(text == "Priority: 2")
        }
        
        @Test("String raw value enum processing returns correct value")
        func stringRawValueEnumProcessing() async throws {
            let server = EnumTestServer()
            let client = MockClient(server: server)
            
            let request = JSONRPCMessage.request(
                id: 2,
                method: "tools/call",
                params: [
                    "name": "processStatus",
                    "arguments": ["status": "active"]
                ]
            )
            
            let response = await client.send(request)
            guard case .response(let responseData) = response else {
                throw TestError("Expected response case")
            }
            
            #expect(responseData.id == .int(2))
            let result = try #require(responseData.result)
            let isError = try #require(result["isError"]?.value as? Bool)
            #expect(isError == false)
            let content = try #require(result["content"]?.value as? [[String: String]])
            let firstContent = try #require(content.first)
            let type = try #require(firstContent["type"])
            let text = try #require(firstContent["text"])
            #expect(type == "text")
            #expect(text == "Status: ACTIVE")
        }
    }
    
    @Suite("Custom String Representation")
    struct CustomStringTests {
        
        @Test("Custom string representation enum shows proper error message")
        func customStringRepresentationEnumErrorMessage() async throws {
            let server = EnumTestServer()
            let client = MockClient(server: server)
            
            let request = JSONRPCMessage.request(
                id: 3,
                method: "tools/call",
                params: [
                    "name": "processSortOrder",
                    "arguments": ["order": "ascending"]
                ]
            )
            
            let response = await client.send(request)
            guard case .response(let responseData) = response else {
                throw TestError("Expected response case")
            }
            
            #expect(responseData.id == .int(3))
            let result = try #require(responseData.result)
            let content = try #require(result["content"]?.value as? [[String: String]])
            let firstContent = try #require(content.first)
            let type = try #require(firstContent["type"])
            let text = try #require(firstContent["text"])
            #expect(type == "text")
            #expect(text == "Parameter 'order' expected one of [SORT_ASC, SORT_DESC] but received ascending")
        }
    }
    
    @Suite("Array Processing")
    struct ArrayTests {
        
        @Test("Array of enums processing returns comma-separated values")
        func arrayOfEnumsProcessing() async throws {
            let server = EnumTestServer()
            let client = MockClient(server: server)
            
            let request = JSONRPCMessage.request(
                id: 4,
                method: "tools/call",
                params: [
                    "name": "processPriorities",
                    "arguments": ["priorities": ["low", "medium", "high"]]
                ]
            )
            
            let response = await client.send(request)
            guard case .response(let responseData) = response else {
                throw TestError("Expected response case")
            }
            
            #expect(responseData.id == .int(4))
            let result = try #require(responseData.result)
            let isError = try #require(result["isError"]?.value as? Bool)
            #expect(isError == false)
            let content = try #require(result["content"]?.value as? [[String: String]])
            let firstContent = try #require(content.first)
            let type = try #require(firstContent["type"])
            let text = try #require(firstContent["text"])
            #expect(type == "text")
            #expect(text == "0,1,2")
        }
        
        @Test("Optional array processing with values returns status text")
        func optionalArrayProcessingWithValues() async throws {
            let server = EnumTestServer()
            let client = MockClient(server: server)
            
            let request = JSONRPCMessage.request(
                id: 5,
                method: "tools/call",
                params: [
                    "name": "processStatus",
                    "arguments": AnyCodable(["status": "active"])
                ]
            )
            
            let response = await client.send(request)
            guard case .response(let responseData) = response else {
                throw TestError("Expected response case")
            }
            
            #expect(responseData.id == .int(5))
            let result = try #require(responseData.result)
            let isError = try #require(result["isError"]?.value as? Bool)
            #expect(isError == false)
            let content = try #require(result["content"]?.value as? [[String: String]])
            let firstContent = try #require(content.first)
            let text = try #require(firstContent["text"])
            #expect(text == "Status: ACTIVE")
        }
        
        @Test("Optional array processing with nil returns empty text")
        func optionalArrayProcessingWithNil() async throws {
            let server = EnumTestServer()
            let client = MockClient(server: server)
            
            let request = JSONRPCMessage.request(
                id: 6,
                method: "tools/call",
                params: [
                    "name": "processOptionalStatuses",
                    "arguments": AnyCodable([:])
                ]
            )
            
            let response = await client.send(request)
            guard case .response(let responseData) = response else {
                throw TestError("Expected response case")
            }
            
            #expect(responseData.id == .int(6))
            let result = try #require(responseData.result)
            let isError = try #require(result["isError"]?.value as? Bool)
            #expect(isError == false)
            let content = try #require(result["content"]?.value as? [[String: String]])
            let firstContent = try #require(content.first)
            let text = try #require(firstContent["text"])
            #expect(text == "empty")
        }
    }
    
    @Suite("Schema Generation", .tags(.schema))
    struct SchemaTests {
        
        @Test("Case labels match raw values for Priority enum")
        func priorityCaseLabelsMatchRawValues() throws {
            let labels = Array<String>(caseLabelsFrom: Priority.self)
            let actualLabels = try #require(labels)
            #expect(actualLabels == ["low", "medium", "high"])
        }
        
        @Test("Case labels match raw values for Status enum")
        func statusCaseLabelsMatchRawValues() throws {
            let labels = Array<String>(caseLabelsFrom: Status.self)
            let actualLabels = try #require(labels)
            #expect(actualLabels == ["pending", "active", "completed"])
        }
        
        @Test("Case labels match raw values for SortOrder enum")
        func sortOrderCaseLabelsMatchRawValues() throws {
            let labels = Array<String>(caseLabelsFrom: SortOrder.self)
            let actualLabels = try #require(labels)
            #expect(actualLabels == ["SORT_ASC", "SORT_DESC"])
        }
        
        @Test("Enum schema generation includes proper constraints")
        func enumSchemaGeneration() throws {
            let server = EnumTestServer()
            let tools = server.mcpToolMetadata.convertedToTools()
            
            // Test priority schema
            let priorityTool = try #require(tools.first { $0.name == "processPriority" })
            
            guard case .object(let object) = priorityTool.inputSchema else {
                throw TestError("Expected object schema")
            }
            
            let prioritySchema = try #require(object.properties["priority"])
            
            guard case .enum(let enumValues, description: _) = prioritySchema else {
                throw TestError("Expected enum schema")
            }
            
            #expect(Set(enumValues) == Set(["low", "medium", "high"]))
        }
    }
}

// MARK: - Test Tags Extension
extension Tag {
    @Tag static var enumType: Self
    @Tag static var schema: Self
} 
