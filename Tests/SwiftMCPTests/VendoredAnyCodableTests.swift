import Foundation
import Testing
import AnyCodable

@Suite("Vendored AnyCodable")
struct VendoredAnyCodableTests {
    @Test("Vendored types remain Sendable")
    func vendoredTypesRemainSendable() {
        assertSendable(AnyCodable.self)
        assertSendable(AnyDecodable.self)
        assertSendable(AnyEncodable.self)
    }

    @Test("AnyCodable round-trips nested JSON values")
    func anyCodableRoundTripsNestedJSONValues() throws {
        let payload: [String: AnyCodable] = [
            "string": AnyCodable("value"),
            "number": AnyCodable(42),
            "array": AnyCodable(["one", "two"]),
            "object": AnyCodable([
                "nested": true,
                "count": 3
            ])
        ]

        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode([String: AnyCodable].self, from: data)

        #expect(decoded["string"]?.value as? String == "value")
        #expect(decoded["number"]?.value as? Int == 42)
        #expect(decoded["array"]?.value as? [String] == ["one", "two"])

        let object = try #require(decoded["object"]?.value as? [String: Any])
        #expect(object["nested"] as? Bool == true)
        #expect(object["count"] as? Int == 3)
    }
}

private func assertSendable<T: Sendable>(_: T.Type) {}
