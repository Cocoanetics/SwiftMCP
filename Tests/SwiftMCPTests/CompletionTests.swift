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
