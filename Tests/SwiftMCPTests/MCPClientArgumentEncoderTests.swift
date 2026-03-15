import Testing
@testable import SwiftMCP

/// An enum conforming to both `Codable` and `CaseIterable` — the exact
/// combination that triggers the compiler ambiguity fixed in issue #74.
private enum Color: String, Codable, CaseIterable {
    case red, green, blue
}

/// An enum conforming only to `CaseIterable` (no `Codable`).
private enum Direction: CaseIterable {
    case north, south, east, west
}

/// An enum conforming only to `Codable` (no `CaseIterable`).
private enum DeployStatus: String, Codable {
    case active, inactive
}

@Suite("MCPClientArgumentEncoder Ambiguity (Issue #74)")
struct MCPClientArgumentEncoderTests {

    @Test("Encode Codable+CaseIterable enum without ambiguity")
    func encodeCodableCaseIterable() throws {
        let result = try MCPClientArgumentEncoder.encode(Color.red)
        // The Encodable path should produce the raw value via JSONValue(encoding:)
        #expect(result == .string("red"))
    }

    @Test("Encode array of Codable+CaseIterable enums without ambiguity")
    func encodeCodableCaseIterableArray() throws {
        let result = try MCPClientArgumentEncoder.encode([Color.green, Color.blue])
        #expect(result == .array([.string("green"), .string("blue")]))
    }

    @Test("Encode CaseIterable-only enum still works")
    func encodeCaseIterableOnly() throws {
        let result = try MCPClientArgumentEncoder.encode(Direction.north)
        #expect(result == .string("north"))
    }

    @Test("Encode Codable-only enum still works")
    func encodeCodableOnly() throws {
        let result = try MCPClientArgumentEncoder.encode(DeployStatus.active)
        #expect(result == .string("active"))
    }
}
