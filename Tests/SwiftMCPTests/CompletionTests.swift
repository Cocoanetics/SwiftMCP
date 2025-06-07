import Foundation
import Testing
@testable import SwiftMCP
import AnyCodable

@MCPServer
class CompletionServer {
    enum Color: CaseIterable {
        case red
        case green
        case blue
    }

    @MCPResource("color://message?color={color}")
    func getColorMessage(color: Color) -> String {
        switch color {
        case .red: return "You selected RED!"
        case .green: return "You selected GREEN!"
        case .blue: return "You selected BLUE!"
        }
    }
}

@MCPServer
class CustomCompletionServer: MCPCompletionProviding {
    enum Color: CaseIterable { case red, green, blue }

    @MCPResource("color://message?color={color}")
    func getColorMessage(color: Color) -> String {
        switch color {
        case .red: return "You selected RED!"
        case .green: return "You selected GREEN!"
        case .blue: return "You selected BLUE!"
        }
    }

    func completion(for parameter: MCPParameterInfo, in context: MCPCompletionContext, prefix: String) async -> CompleteResult.Completion {
        if parameter.name == "color" {
            
            let completions = parameter.defaultCompletions + ["ruby", "rose"]
            
            return CompleteResult.Completion(values: completions.sortedByBestCompletion(prefix: prefix), total: completions.count, hasMore: false)
        }
        
        let completions = parameter.defaultCompletions
        return CompleteResult.Completion(values: completions.sortedByBestCompletion(prefix: prefix), total: completions.count, hasMore: false)
    }
}

@Suite("Completion Tests", .tags(.completion, .unit))
struct CompletionTests {
    
    @Test("Enum completion returns case labels with prefix match first")
    func enumCompletionReturnsCaseLabelsWithPrefixFirst() async throws {
        let server = CompletionServer()

        let request = JSONRPCMessage.request(
            id: 1,
            method: "completion/complete",
            params: [
                "argument": ["name": "color", "value": "r"],
                "ref": ["type": "ref/resource", "uri": "color://message?color={color}"]
            ]
        )

        let message = try #require(await server.handleMessage(request))
        
        guard case .response(let response) = message else {
            throw TestError("Expected response")
        }

        let result = try #require(response.result)
        let comp = try #require(result["completion"]?.value as? [String: Any])
        let values = try #require(comp["values"] as? [String])

        #expect(values == ["red", "green", "blue"])
    }

    @Test("Custom completion provider returns custom values")
    func customCompletionProviderReturnsCustomValues() async throws {
        let server = CustomCompletionServer()

        let request = JSONRPCMessage.request(
            id: 1,
            method: "completion/complete",
            params: [
                "argument": ["name": "color", "value": "ru"],
                "ref": ["type": "ref/resource", "uri": "color://message?color={color}"]
            ]
        )

        let message = try #require(await server.handleMessage(request))
        
        guard case .response(let response) = message else {
            throw TestError("Expected response")
        }

        let result = try #require(response.result)
        let comp = try #require(result["completion"]?.value as? [String: Any])
        let values = try #require(comp["values"] as? [String])

        #expect(values.first == "ruby")
        #expect(values.contains("red"))
        #expect(values.count == 5)
    }

    @Test("Completion sorting prefers longer prefix matches")
    func completionSortingPrefersLongerPrefixMatches() {
        let sorted = ["red", "green", "blue", "ruby"].sortedByBestCompletion(prefix: "re")
        #expect(sorted.first == "red")
        #expect(sorted[1] == "ruby")
    }
}

// MARK: - Test Tags Extension
extension Tag {
    @Tag static var completion: Self
}


