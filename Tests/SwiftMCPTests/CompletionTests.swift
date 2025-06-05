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
            let defaults = defaultEnumCompletion(for: parameter, prefix: prefix)?.values ?? []
            let extra = ["ruby", "rose"].filter { $0.hasPrefix(prefix) }.sortedByBestCompletion(prefix: prefix)
            let all = extra + defaults
            return CompleteResult.Completion(values: all, total: all.count, hasMore: false)
        }
        return defaultEnumCompletion(for: parameter, prefix: prefix) ?? CompleteResult.Completion(values: [])
    }
}

@Test("Enum completion returns case labels with prefix match first")
func testEnumCompletion() async throws {
    let server = CompletionServer()

    let request = JSONRPCMessage.request(
        id: 1,
        method: "completion/complete",
        params: [
            "argument": ["name": "color", "value": "r"],
            "ref": ["type": "ref/resource", "uri": "color://message?color={color}"]
        ]
    )

    guard let message = await server.handleMessage(request),
          case .response(let response) = message else {
        #expect(Bool(false), "Expected response")
        return
    }

    let result = unwrap(response.result)
    let comp = unwrap(result["completion"]?.value as? [String: Any])
    let values = unwrap(comp["values"] as? [String])

    #expect(values == ["red", "green", "blue"])
}

@Test("Custom completion provider returns custom values")
func testCustomCompletionProvider() async throws {
    let server = CustomCompletionServer()

    let request = JSONRPCMessage.request(
        id: 1,
        method: "completion/complete",
        params: [
            "argument": ["name": "color", "value": "r"],
            "ref": ["type": "ref/resource", "uri": "color://message?color={color}"]
        ]
    )

    guard let message = await server.handleMessage(request),
          case .response(let response) = message else {
        #expect(Bool(false), "Expected response")
        return
    }

    let result = unwrap(response.result)
    let comp = unwrap(result["completion"]?.value as? [String: Any])
    let values = unwrap(comp["values"] as? [String])

    #expect(values.first == "ruby")
    #expect(values.contains("red"))
    #expect(values.count == 5)
}

@Test("Completion sorting prefers longer prefix matches")
func testSortedByBestCompletion() {
    let sorted = ["red", "green", "blue", "ruby"].sortedByBestCompletion(prefix: "re")
    #expect(sorted.first == "red")
    #expect(sorted[1] == "ruby")
}
