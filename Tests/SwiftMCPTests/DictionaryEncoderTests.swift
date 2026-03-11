import Foundation
import Testing
@testable import SwiftMCP

struct TestStruct: Codable, Equatable {
    let intValue: Int
    let stringValue: String
    let boolValue: Bool
    let doubleValue: Double
}

struct NestedStruct: Codable, Equatable {
    let name: String
    let inner: TestStruct
}

@Test("JSONDictionary encodes flat struct")
func testFlatStruct() throws {
    let value = TestStruct(intValue: 42, stringValue: "hello", boolValue: true, doubleValue: 3.14)
    let dict = try JSONDictionary(encoding: value)
    #expect(dict["intValue"]?.value as? Int == 42)
    #expect(dict["stringValue"]?.value as? String == "hello")
    #expect(dict["boolValue"]?.value as? Bool == true)
    #expect(dict["doubleValue"]?.value as? Double == 3.14)
}

@Test("JSONDictionary encodes nested struct")
func testNestedStruct() throws {
    let value = NestedStruct(name: "outer", inner: TestStruct(intValue: 1, stringValue: "inner", boolValue: false, doubleValue: 2.71))
    let dict = try JSONDictionary(encoding: value)
    #expect(dict["name"]?.value as? String == "outer")
    let inner = dict["inner"]?.value as? [String: Any]
    #expect(inner?["intValue"] as? Int == 1)
    #expect(inner?["stringValue"] as? String == "inner")
    #expect(inner?["boolValue"] as? Bool == false)
    #expect(inner?["doubleValue"] as? Double == 2.71)
}

@Test("JSONDictionary encodes arrays and omits nil optionals")
func testArraysAndOptionals() throws {
    struct ArrayStruct: Codable {
        let items: [Int]
        let optional: String?
    }
    let value = ArrayStruct(items: [1, 2, 3], optional: nil)
    let dict = try JSONDictionary(encoding: value)
    #expect(dict["items"]?.value as? [Int] == [1, 2, 3])
    #expect(dict["optional"] == nil)
}

@Test("JSONDictionary encodes non-nil optionals")
func testNonNilOptionals() throws {
    struct OptionalStruct: Codable {
        let value: String?
        let number: Int?
    }
    let value = OptionalStruct(value: "present", number: nil)
    let dict = try JSONDictionary(encoding: value)
    #expect(dict["value"]?.value as? String == "present")
    #expect(dict["number"] == nil)
}

@Test("JSONDictionary uses MCP JSON coding policy for Date and Data")
func testDateAndData() throws {
    struct SpecialStruct: Codable {
        let date: Date
        let data: Data
    }
    let now = Date(timeIntervalSince1970: 1234567890)
    let bytes = Data([0x01, 0x02, 0x03])
    let value = SpecialStruct(date: now, data: bytes)
    let dict = try JSONDictionary(encoding: value)

    #expect(dict["date"]?.stringValue == MCPToolArgumentEncoder.encode(now))
    #expect(dict["data"]?.stringValue == bytes.base64EncodedString())
}

@Test("JSONDictionary preserves boolean JSON encoding")
func testBooleanJSONEncoding() throws {
    struct BoolStruct: Codable {
        let flag: Bool
    }
    let value = BoolStruct(flag: true)
    let dict = try JSONDictionary(encoding: value)
    let jsonData = try JSONEncoder().encode(dict)
    let jsonObject = try JSONSerialization.jsonObject(with: jsonData, options: [])
    let jsonDict = jsonObject as? [String: Any]
    #expect(jsonDict?["flag"] as? Bool == true)
}
