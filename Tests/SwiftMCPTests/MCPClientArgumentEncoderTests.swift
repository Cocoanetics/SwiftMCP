import Testing
@testable import SwiftMCP

/// An enum conforming to both `Codable` and `CaseIterable` with raw values
/// that differ from the case labels — the exact combination that triggered
/// issue #74 and the encode/decode mismatch.
private enum Urgency: String, Codable, CaseIterable {
    case high = "H"
    case medium = "M"
    case low = "L"
}

/// A simpler dual-conforming enum where raw values equal case labels.
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

    // MARK: - Dual conformance (Codable + CaseIterable)

    @Test("Encode Codable+CaseIterable enum uses case label, not raw value")
    func encodeDualConformingUsesLabel() throws {
        // Urgency.high has rawValue "H", but MCP expects "high"
        let result = try MCPClientArgumentEncoder.encode(Urgency.high)
        #expect(result == .string("high"), "Must encode as case label, not raw value 'H'")
    }

    @Test("Encode all Codable+CaseIterable cases uses labels")
    func encodeDualConformingAllCases() throws {
        let results = try Urgency.allCases.map { try MCPClientArgumentEncoder.encode($0) }
        #expect(results == [.string("high"), .string("medium"), .string("low")])
    }

    @Test("Encode array of Codable+CaseIterable enums uses labels")
    func encodeDualConformingArray() throws {
        let result = try MCPClientArgumentEncoder.encode([Urgency.high, Urgency.low])
        #expect(result == .array([.string("high"), .string("low")]))
    }

    @Test("Encode Codable+CaseIterable enum without ambiguity")
    func encodeCodableCaseIterable() throws {
        let result = try MCPClientArgumentEncoder.encode(Color.red)
        #expect(result == .string("red"))
    }

    @Test("Encode array of Codable+CaseIterable enums without ambiguity")
    func encodeCodableCaseIterableArray() throws {
        let result = try MCPClientArgumentEncoder.encode([Color.green, Color.blue])
        #expect(result == .array([.string("green"), .string("blue")]))
    }

    // MARK: - Single conformance (no regression)

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

    // MARK: - Round-trip consistency with decoding

    @Test("Encoded label matches what parameter decoding expects")
    func roundTripConsistency() throws {
        // Simulate what parameter extraction does: validate against caseLabels
        let caseLabels = Urgency.allCases.map { String(describing: $0) }
        let encoded = try MCPClientArgumentEncoder.encode(Urgency.medium)

        guard case .string(let label) = encoded else {
            Issue.record("Expected string value")
            return
        }

        #expect(caseLabels.contains(label),
                "Encoded value '\(label)' must be in caseLabels: \(caseLabels)")
    }
}
