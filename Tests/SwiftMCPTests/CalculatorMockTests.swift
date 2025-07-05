import Foundation
import Testing
@testable import SwiftMCP
import AnyCodable

@Suite("Calculator Mock Client Tests", .tags(.calculator, .mockClient, .unit))
struct CalculatorMockTests {
    
    @Suite("Basic Arithmetic Operations")
    struct BasicArithmeticTests {
        
        @Test("Add function returns correct sum")
        func addFunctionReturnsCorrectSum() async throws {
            let calculator = Calculator()
            let client = MockClient(server: calculator)
            
            let request = JSONRPCMessage.request(
                id: 1,
                method: "tools/call",
                params: [
                    "name": "add",
                    "arguments": ["a": 2, "b": 3]
                ]
            )
            
            let message = await client.send(request)
            guard case .response(let response) = message else {
                throw TestError("Expected response case")
            }
            
            #expect(response.id == .int(1))
            let result = try #require(response.result)
            let isError = try #require(result["isError"]?.value as? Bool)
            #expect(isError == false)
            let content = try #require(result["content"]?.value as? [[String: String]])
            let firstContent = try #require(content.first)
            let type = try #require(firstContent["type"])
            let text = try #require(firstContent["text"])
            #expect(type == "text")
            #expect(text == "5")
        }

        @Test("Subtract function returns correct difference")
        func subtractFunctionReturnsCorrectDifference() async throws {
            let calculator = Calculator()
            let client = MockClient(server: calculator)
            
            let request = JSONRPCMessage.request(
                id: 1,
                method: "tools/call",
                params: [
                    "name": "subtract",
                    "arguments": ["a": 10, "b": 4]
                ]
            )
            
            let message = try #require(await client.send(request))
            guard case .response(let response) = message else {
                throw TestError("Expected response case")
            }
            
            #expect(response.id == .int(1))
            let result = try #require(response.result)
            let isError = try #require(result["isError"]?.value as? Bool)
            #expect(isError == false)
            let content = try #require(result["content"]?.value as? [[String: String]])
            let firstContent = try #require(content.first)
            let type = try #require(firstContent["type"])
            let text = try #require(firstContent["text"])
            #expect(type == "text")
            #expect(text == "6")
        }

        @Test("Multiply function returns correct product")
        func multiplyFunctionReturnsCorrectProduct() async throws {
            let calculator = Calculator()
            let client = MockClient(server: calculator)
            
            let request = JSONRPCMessage.request(
                id: 1,
                method: "tools/call",
                params: [
                    "name": "multiply",
                    "arguments": ["a": 6, "b": 7]
                ]
            )
            
            let message = try #require(await client.send(request))
            guard case .response(let response) = message else {
                throw TestError("Expected response case")
            }
            
            #expect(response.id == .int(1))
            let result = try #require(response.result)
            let isError = try #require(result["isError"]?.value as? Bool)
            #expect(isError == false)
            let content = try #require(result["content"]?.value as? [[String: String]])
            let firstContent = try #require(content.first)
            let type = try #require(firstContent["type"])
            let text = try #require(firstContent["text"])
            #expect(type == "text")
            #expect(text == "42")
        }

        @Test("Divide function returns correct quotient")
        func divideFunctionReturnsCorrectQuotient() async throws {
            let calculator = Calculator()
            let client = MockClient(server: calculator)
            
            let request = JSONRPCMessage.request(
                id: 1,
                method: "tools/call",
                params: [
                    "name": "divide",
                    "arguments": ["numerator": 10, "denominator": 2]
                ]
            )
            
            let message = try #require(await client.send(request))
            guard case .response(let response) = message else {
                throw TestError("Expected response case")
            }
            
            #expect(response.id == .int(1))
            let result = try #require(response.result)
            let isError = try #require(result["isError"]?.value as? Bool)
            #expect(isError == false)
            let content = try #require(result["content"]?.value as? [[String: String]])
            let firstContent = try #require(content.first)
            let type = try #require(firstContent["type"])
            let text = try #require(firstContent["text"])
            #expect(type == "text")
            #expect(text == "5")
        }
    }
    
    @Suite("String and Array Operations")
    struct StringAndArrayTests {
        
        @Test("Greet function returns personalized greeting")
        func greetFunctionReturnsPersonalizedGreeting() async throws {
            let calculator = Calculator()
            let client = MockClient(server: calculator)
            
            let request = JSONRPCMessage.request(
                id: 1,
                method: "tools/call",
                params: [
                    "name": "greet",
                    "arguments": ["name": "Oliver"]
                ]
            )
            
            let message = try #require(await client.send(request))
            guard case .response(let response) = message else {
                throw TestError("Expected response case")
            }
            
            #expect(response.id == .int(1))
            let result = try #require(response.result)
            let isError = try #require(result["isError"]?.value as? Bool)
            #expect(isError == false)
            let content = try #require(result["content"]?.value as? [[String: String]])
            let firstContent = try #require(content.first)
            let type = try #require(firstContent["type"])
            let text = try #require(firstContent["text"])
            #expect(type == "text")
            #expect(text == "Hello, Oliver!")
        }

        @Test("Test array function processes array correctly")
        func testArrayFunctionProcessesArrayCorrectly() async throws {
            let calculator = Calculator()
            let client = MockClient(server: calculator)
            
            let request = JSONRPCMessage.request(
                id: 1,
                method: "tools/call",
                params: [
                    "name": "testArray",
                    "arguments": ["a": [1, 2, 3, 4, 5]]
                ]
            )
            
            let message = try #require(await client.send(request))
            guard case .response(let response) = message else {
                throw TestError("Expected response case")
            }
            
            #expect(response.id == .int(1))
            let result = try #require(response.result)
            let isError = try #require(result["isError"]?.value as? Bool)
            #expect(isError == false)
            let content = try #require(result["content"]?.value as? [[String: String]])
            let firstContent = try #require(content.first)
            let type = try #require(firstContent["type"])
            let text = try #require(firstContent["text"])
            #expect(type == "text")
            #expect(text == "1, 2, 3, 4, 5")
        }
    }
    
    @Suite("Error Handling Tests")
    struct ErrorHandlingTests {
        
        @Test("Division by zero returns infinity")
        func divisionByZeroReturnsInfinity() async throws {
            let calculator = Calculator()
            let client = MockClient(server: calculator)
            
            let request = JSONRPCMessage.request(
                id: 1,
                method: "tools/call",
                params: [
                    "name": "divide",
                    "arguments": ["numerator": 10, "denominator": 0]
                ]
            )
            
            let message = try #require(await client.send(request))
            guard case .response(let response) = message else {
                throw TestError("Expected response case")
            }
            
            #expect(response.id == .int(1))
            let result = try #require(response.result)
            let isError = try #require(result["isError"]?.value as? Bool)
            #expect(isError == false)
            let content = try #require(result["content"]?.value as? [[String: String]])
            let firstContent = try #require(content.first)
            let type = try #require(firstContent["type"])
            let text = try #require(firstContent["text"])
            #expect(type == "text")
            #expect(text == "Infinity")
        }
        
        @Test("Negative division by zero returns negative infinity")
        func negativeDivisionByZeroReturnsNegativeInfinity() async throws {
            let calculator = Calculator()
            let client = MockClient(server: calculator)
            
            let request = JSONRPCMessage.request(
                id: 1,
                method: "tools/call",
                params: [
                    "name": "divide",
                    "arguments": ["numerator": -10, "denominator": 0]
                ]
            )
            
            let message = try #require(await client.send(request))
            guard case .response(let response) = message else {
                throw TestError("Expected response case")
            }
            
            let result = try #require(response.result)
            let isError = try #require(result["isError"]?.value as? Bool)
            #expect(isError == false)
            let content = try #require(result["content"]?.value as? [[String: String]])
            let firstContent = try #require(content.first)
            let text = try #require(firstContent["text"])
            #expect(text == "-Infinity")
        }
        
        @Test("Zero divided by zero returns NaN")
        func zeroDividedByZeroReturnsNaN() async throws {
            let calculator = Calculator()
            let client = MockClient(server: calculator)
            
            let request = JSONRPCMessage.request(
                id: 1,
                method: "tools/call",
                params: [
                    "name": "divide",
                    "arguments": ["numerator": 0, "denominator": 0]
                ]
            )
            
            let message = try #require(await client.send(request))
            guard case .response(let response) = message else {
                throw TestError("Expected response case")
            }
            
            let result = try #require(response.result)
            let isError = try #require(result["isError"]?.value as? Bool)
            #expect(isError == false)
            let content = try #require(result["content"]?.value as? [[String: String]])
            let firstContent = try #require(content.first)
            let text = try #require(firstContent["text"])
            #expect(text == "NaN")
        }
        
        @Test("Invalid tool name returns error")
        func invalidToolNameReturnsError() async throws {
            let calculator = Calculator()
            let client = MockClient(server: calculator)
            
            let request = JSONRPCMessage.request(
                id: 1,
                method: "tools/call",
                params: [
                    "name": "invalidTool",
                    "arguments": [:]
                ]
            )
            
            let message = try #require(await client.send(request))
            guard case .response(let response) = message else {
                throw TestError("Expected response case")
            }
            
            #expect(response.id == .int(1))
            let result = try #require(response.result)
            let isError = try #require(result["isError"]?.value as? Bool)
            #expect(isError == true)
            let content = try #require(result["content"]?.value as? [[String: String]])
            let firstContent = try #require(content.first)
            let type = try #require(firstContent["type"])
            let text = try #require(firstContent["text"])
            #expect(type == "text")
            #expect(text.contains("The tool 'invalidTool' was not found on the server"))
        }
    }
    
    @Suite("Complex Operations")
    struct ComplexOperationTests {
        
        @Test("Complex calculation with multiple steps")
        func complexCalculationWithMultipleSteps() async throws {
            let calculator = Calculator()
            let client = MockClient(server: calculator)
            
            // First operation: 5 + 3 = 8
            let addRequest = JSONRPCMessage.request(
                id: 1,
                method: "tools/call",
                params: [
                    "name": "add",
                    "arguments": ["a": 5, "b": 3]
                ]
            )
            
            let addMessage = try #require(await client.send(addRequest))
            guard case .response(let addResponse) = addMessage else {
                throw TestError("Expected response case")
            }
            
            let addResult = try #require(addResponse.result)
            let addContent = try #require(addResult["content"]?.value as? [[String: String]])
            let addText = try #require(addContent.first?["text"])
            #expect(addText == "8")
            
            // Second operation: 8 * 2 = 16
            let multiplyRequest = JSONRPCMessage.request(
                id: 2,
                method: "tools/call",
                params: [
                    "name": "multiply",
                    "arguments": ["a": 8, "b": 2]
                ]
            )
            
            let multiplyMessage = try #require(await client.send(multiplyRequest))
            guard case .response(let multiplyResponse) = multiplyMessage else {
                throw TestError("Expected response case")
            }
            
            let multiplyResult = try #require(multiplyResponse.result)
            let multiplyContent = try #require(multiplyResult["content"]?.value as? [[String: String]])
            let multiplyText = try #require(multiplyContent.first?["text"])
            #expect(multiplyText == "16")
        }
    }
}

// MARK: - Test Tags Extension
extension Tag {
    @Tag static var calculator: Self
    @Tag static var mockClient: Self
}
