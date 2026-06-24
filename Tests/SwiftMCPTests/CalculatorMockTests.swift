import Foundation
import Testing
@testable import SwiftMCP

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

            #expect(response.id == .integer(1))
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

            #expect(response.id == .integer(1))
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

            #expect(response.id == .integer(1))
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

            #expect(response.id == .integer(1))
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

            #expect(response.id == .integer(1))
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

            #expect(response.id == .integer(1))
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

}

// MARK: - Test Tags Extension
extension Tag {
    @Tag static var calculator: Self
    @Tag static var mockClient: Self
}
