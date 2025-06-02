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

@Suite("Enum Tests")
struct EnumTests {
    @Test("Test integer raw value enum")
    func testIntegerRawValueEnum() async throws {
        let server = EnumTestServer()
        let client = MockClient(server: server)
        
        let request = JSONRPCMessage.request(
            id: 1,
            method: "tools/call",
            params: [
                "name": AnyCodable("getBasicEnum"),
                "arguments": AnyCodable([String: Any]())
            ]
        )
        
        let response = unwrap(await client.send(request))
        
        guard case .response(let responseData) = response else {
            #expect(Bool(false), "Expected response case")
            return
        }
        
        #expect(responseData.id == 1)
        
        let result = unwrap(responseData.result)
        let isError = unwrap(result["isError"]?.value as? Bool)
        #expect(isError == false)
        
        let content = unwrap(result["content"]?.value as? [[String: String]])
        let firstContent = unwrap(content.first) as [String: String]
        let type = unwrap(firstContent["type"]) as String
        let text = unwrap(firstContent["text"]) as String
        
        #expect(type == "text")
        #expect(text == "Priority: 2")
    }
    
    @Test("Test string raw value enum")
    func testStringRawValueEnum() async throws {
        let server = EnumTestServer()
        let client = MockClient(server: server)
        
        let request = JSONRPCMessage.request(
            id: 2,
            method: "tools/call",
            params: [
                "name": AnyCodable("getConditionalEnum"),
                "arguments": AnyCodable(["condition": true])
            ]
        )
        
        let response = unwrap(await client.send(request))
        
        guard case .response(let responseData) = response else {
            #expect(Bool(false), "Expected response case")
            return
        }
        
        #expect(responseData.id == 2)
        
        let result = unwrap(responseData.result)
        let isError = unwrap(result["isError"]?.value as? Bool)
        #expect(isError == false)
        
        let content = unwrap(result["content"]?.value as? [[String: String]])
        let firstContent = unwrap(content.first) as [String: String]
        let type = unwrap(firstContent["type"]) as String
        let text = unwrap(firstContent["text"]) as String
        
        #expect(type == "text")
        #expect(text == "Status: ACTIVE")
    }
    
    @Test("Test custom string representation enum")
    func testCustomStringRepresentationEnum() async throws {
        let server = EnumTestServer()
        let client = MockClient(server: server)
        
        let request = JSONRPCMessage.request(
            id: 3,
            method: "tools/call",
            params: [
                "name": AnyCodable("getNestedEnum"),
                "arguments": AnyCodable([String: Any]())
            ]
        )
        
        let response = unwrap(await client.send(request))
        
        guard case .response(let responseData) = response else {
            #expect(Bool(false), "Expected response case")
            return
        }
        
        #expect(responseData.id == 3)
        
        let result = unwrap(responseData.result)
        let isError = unwrap(result["isError"]?.value as? Bool)
        #expect(isError == false)
        
        let content = unwrap(result["content"]?.value as? [[String: String]])
        let firstContent = unwrap(content.first) as [String: String]
        let type = unwrap(firstContent["type"]) as String
        let text = unwrap(firstContent["text"]) as String
        
        #expect(type == "text")
        #expect(text == "Order: SORT_ASC")
    }
    
    @Test("Test array of enums")
    func testArrayOfEnums() async throws {
        let server = EnumTestServer()
        let client = MockClient(server: server)
        
        let request = JSONRPCMessage.request(
            id: 4,
            method: "tools/call",
            params: [
                "name": "processPriorities",
                "arguments": [
                    "priorities": ["low", "medium", "high"]
                ]
            ]
        )
        
        let response = unwrap(await client.send(request) as? JSONRPCResponse)
        
        #expect(response.id == 4)
        
        guard let result = response.result else {
            throw TestError("Expected result to be non-nil")
        }
        
        let isError = unwrap(result["isError"]?.value as? Bool)
        #expect(isError == false)
        
        let content = unwrap(result["content"]?.value as? [[String: String]])
        let firstContent = unwrap(content.first) as [String: String]
        let type = unwrap(firstContent["type"]) as String
        let text = unwrap(firstContent["text"]) as String
        
        #expect(type == "text")
        #expect(text == "0,1,2")
    }
    
    @Test("Test optional array of enums")
    func testOptionalArrayOfEnums() async throws {
        let server = EnumTestServer()
        let client = MockClient(server: server)
        
        // Test with values
        let requestWithValues = JSONRPCMessage.request(
            id: 5,
            method: "tools/call",
            params: [
                "name": AnyCodable("processStatus"),
                "arguments": AnyCodable(["status": "active"])
            ]
        )
        
        let responseWithValues = unwrap(await client.send(requestWithValues))
        
        guard case .response(let responseDataWithValues) = responseWithValues else {
            #expect(Bool(false), "Expected response case")
            return
        }
        
        #expect(responseDataWithValues.id == 5)
        
        let resultWithValues = unwrap(responseDataWithValues.result)
        let isErrorWithValues = unwrap(resultWithValues["isError"]?.value as? Bool)
        #expect(isErrorWithValues == false)
        
        let contentWithValues = unwrap(resultWithValues["content"]?.value as? [[String: String]])
        let firstContentWithValues = unwrap(contentWithValues.first) as [String: String]
        let textWithValues = unwrap(firstContentWithValues["text"]) as String
        
        #expect(textWithValues == "ACTIVE")
        
        // Test with nil
        let requestWithNil = JSONRPCMessage.request(
            id: 6,
            method: "tools/call",
            params: [
                "name": AnyCodable("testNilOptional"),
                "arguments": AnyCodable(["value": AnyCodable(nil)])
            ]
        )
        
        let responseWithNil = unwrap(await client.send(requestWithNil))
        
        guard case .response(let responseDataWithNil) = responseWithNil else {
            #expect(Bool(false), "Expected response case")
            return
        }
        
        #expect(responseDataWithNil.id == 6)
        
        let resultWithNil = unwrap(responseDataWithNil.result)
        let isErrorWithNil = unwrap(resultWithNil["isError"]?.value as? Bool)
        #expect(isErrorWithNil == false)
        
        let contentWithNil = unwrap(resultWithNil["content"]?.value as? [[String: String]])
        let firstContentWithNil = unwrap(contentWithNil.first) as [String: String]
        let textWithNil = unwrap(firstContentWithNil["text"]) as String
        
        #expect(textWithNil == "nil")
    }
    
    @Test("Test case labels match raw values")
    func testCaseLabelsMatchRawValues() throws {
        // Test integer raw values
        let priorityLabels = Array<String>(caseLabelsFrom: Priority.self)
        #expect(priorityLabels != nil)
        #expect(priorityLabels == ["low", "medium", "high"])
        
        // Test string raw values
        let statusLabels = Array<String>(caseLabelsFrom: Status.self)
        #expect(statusLabels != nil)
        #expect(statusLabels == ["pending", "active", "completed"])
        
        // Test custom string representation
        let sortOrderLabels = Array<String>(caseLabelsFrom: SortOrder.self)
        #expect(sortOrderLabels != nil)
        #expect(sortOrderLabels == ["SORT_ASC", "SORT_DESC"])
    }
    
    @Test("Test enum schema generation")
    func testEnumSchemaGeneration() throws {
        let server = EnumTestServer()
        let tools = server.mcpToolMetadata.convertedToTools()
        
        // Test priority schema
        if let priorityTool = tools.first(where: { $0.name == "processPriority" }) {
            if case .object(let object) = priorityTool.inputSchema {
                if let prioritySchema = object.properties["priority"] {
                    if case .enum(let enumValues, description: _) = prioritySchema {
                        #expect(enumValues.sorted() == ["low", "medium", "high"].sorted())
                    } else {
                        #expect(Bool(false), "Expected string schema with enum values")
                    }
                } else {
                    #expect(Bool(false), "Could not find priority parameter in schema")
                }
            } else {
                #expect(Bool(false), "Expected object schema")
            }
        } else {
            #expect(Bool(false), "Could not find processPriority tool")
        }
        
        // Test status schema
        if let statusTool = tools.first(where: { $0.name == "processStatus" }) {
            if case .object(let object) = statusTool.inputSchema {
                if let statusSchema = object.properties["status"] {
                    if case .enum(let values, description: _) = statusSchema {
                        #expect(values.sorted() == ["pending", "active", "completed"].sorted())
                    } else {
                        #expect(Bool(false), "Expected string schema with enum values")
                    }
                } else {
                    #expect(Bool(false), "Could not find status parameter in schema")
                }
            } else {
                #expect(Bool(false), "Expected object schema")
            }
        } else {
            #expect(Bool(false), "Could not find processStatus tool")
        }
    }
} 
