import Foundation
import Testing
@testable import SwiftMCP

@Suite("Calculator Mock Error Handling and Complex Tests", .tags(.calculator, .mockClient, .unit))
struct CalculatorMockErrorTests {

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

            #expect(response.id == .integer(1))
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

            #expect(response.id == .integer(1))
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
