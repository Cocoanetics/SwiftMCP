import Foundation
import Testing
@testable import SwiftMCP

@Suite("JSONValue")
struct JSONValueTests {
    @Test("JSONValue remains Sendable")
    func jsonValueRemainsSendable() {
        assertSendable(JSONValue.self)
    }

    @Test("JSONValue round-trips nested JSON values")
    func jsonValueRoundTripsNestedJSONValues() throws {
        let payload: JSONDictionary = [
            "string": "value",
            "number": 42,
            "array": .array(["one", "two"]),
            "object": .object([
                "nested": true,
                "count": 3
            ])
        ]

        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(JSONDictionary.self, from: data)

        #expect(decoded["string"]?.value as? String == "value")
        #expect(decoded["number"]?.value as? Int == 42)
        #expect(decoded["array"]?.value as? [String] == ["one", "two"])

        let object = try #require(decoded["object"]?.value as? [String: Any])
        #expect(object["nested"] as? Bool == true)
        #expect(object["count"] as? Int == 3)
    }

    @Test("JSONValue can decode typed values from stored JSON")
    func jsonValueCanDecodeTypedValues() throws {
        let tools = [
            MCPTool(name: "echo", description: "Echo text", inputSchema: .object(.init(properties: [:], required: []))),
            MCPTool(name: "sum", description: "Add numbers", inputSchema: .object(.init(properties: [:], required: [])))
        ]

        let wrapped = try JSONValue(encoding: tools)
        let decoded = try wrapped.decoded([MCPTool].self)

        #expect(decoded.map { $0.name } == ["echo", "sum"])
    }

    @Test("JSONDictionary initializer rejects non-object top-level values")
    func jsonDictionaryInitializerRejectsNonObjectTopLevelValues() {
        struct ScalarValue: Encodable { let value: Int }

        #expect(throws: JSONValueError.expectedObject) {
            _ = try JSONDictionary(encoding: [ScalarValue(value: 1)])
        }
    }
}

private func assertSendable<T: Sendable>(_: T.Type) {}
