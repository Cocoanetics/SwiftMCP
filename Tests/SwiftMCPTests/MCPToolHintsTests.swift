//
//  MCPToolHintsTests.swift
//  SwiftMCP
//
//  Created by Orbit on 02.02.26.
//

import Foundation
import Testing
@testable import SwiftMCP

// MARK: - Test Server with Tool Hints

@MCPServer(name: "HintsTestServer", version: "1.0.0")
class HintsTestServer {

    /// A read-only search function that doesn't modify anything
    @MCPTool(hints: [.readOnly])
    func searchItems(query: String) -> [String] {
        return ["result1", "result2"]
    }

    /// A destructive operation that deletes data
    @MCPTool(hints: [.destructive])
    func deleteAccount(id: String) -> Bool {
        return true
    }

    /// An idempotent update operation
    @MCPTool(hints: [.idempotent])
    func updateSetting(key: String, value: String) -> Bool {
        return true
    }

    /// A tool that interacts with external systems
    @MCPTool(hints: [.openWorld])
    func sendEmail(to: String, message: String) -> Bool {
        return true
    }

    /// A destructive open-world operation (e.g., delete from external system)
    @MCPTool(hints: [.destructive, .openWorld])
    func deleteExternalResource(id: String) -> Bool {
        return true
    }

    /// A read-only and destructive tool (destructive should override for consequential)
    @MCPTool(hints: [.readOnly, .destructive])
    func readOnlyWithDestructive() -> String {
        return "test"
    }

    /// A tool with all hints
    @MCPTool(hints: [.readOnly, .destructive, .idempotent, .openWorld])
    func allHints() -> String {
        return "test"
    }

    /// A tool without any hints (no annotations)
    @MCPTool
    func noHints() -> String {
        return "test"
    }
}

// MARK: - MCPToolHints OptionSet Tests

@Test("MCPToolHints OptionSet has correct raw values")
func testMCPToolHintsRawValues() {
    #expect(MCPToolHints.readOnly.rawValue == 1)
    #expect(MCPToolHints.destructive.rawValue == 2)
    #expect(MCPToolHints.idempotent.rawValue == 4)
    #expect(MCPToolHints.openWorld.rawValue == 8)
}

@Test("MCPToolHints can be combined")
func testMCPToolHintsCombinations() {
    let combined: MCPToolHints = [.readOnly, .destructive]
    #expect(combined.contains(.readOnly))
    #expect(combined.contains(.destructive))
    #expect(!combined.contains(.idempotent))
    #expect(!combined.contains(.openWorld))
}

@Test("MCPToolHints empty set")
func testMCPToolHintsEmpty() {
    let empty: MCPToolHints = []
    #expect(empty.isEmpty)
    #expect(!empty.contains(.readOnly))
    #expect(!empty.contains(.destructive))
}

// MARK: - MCPToolAnnotations Tests

@Test("MCPToolAnnotations init from hints OptionSet")
func testMCPToolAnnotationsFromHints() {
    let annotations = MCPToolAnnotations(hints: [.readOnly, .destructive])

    #expect(annotations.hints.contains(.readOnly))
    #expect(annotations.hints.contains(.destructive))
    #expect(annotations.readOnlyHint == true)
    #expect(annotations.destructiveHint == true)
    #expect(annotations.idempotentHint == nil)
    #expect(annotations.openWorldHint == nil)
}

@Test("MCPToolAnnotations backwards compatible init")
func testMCPToolAnnotationsBackwardsCompat() {
    let annotations = MCPToolAnnotations(
        readOnlyHint: true,
        destructiveHint: true
    )

    #expect(annotations.hints.contains(.readOnly))
    #expect(annotations.hints.contains(.destructive))
    #expect(!annotations.hints.contains(.idempotent))
    #expect(!annotations.hints.contains(.openWorld))
}

@Test("MCPToolAnnotations isEmpty for empty hints")
func testMCPToolAnnotationsIsEmpty() {
    let empty = MCPToolAnnotations(hints: [])
    #expect(empty.isEmpty)

    let notEmpty = MCPToolAnnotations(hints: [.readOnly])
    #expect(!notEmpty.isEmpty)
}

// MARK: - JSON Encoding Tests

@Test("MCPToolAnnotations encodes to JSON wire format")
func testMCPToolAnnotationsJSONEncoding() throws {
    let annotations = MCPToolAnnotations(hints: [.readOnly, .destructive])

    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let data = try encoder.encode(annotations)
    let json = String(data: data, encoding: .utf8)!

    // Should produce wire format with hint names, not raw integers
    #expect(json.contains("readOnlyHint"))
    #expect(json.contains("destructiveHint"))
    #expect(!json.contains("rawValue"))

    // Parse JSON and verify structure
    let decoded = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    #expect(decoded["readOnlyHint"] as? Bool == true)
    #expect(decoded["destructiveHint"] as? Bool == true)
    #expect(decoded["idempotentHint"] == nil)
    #expect(decoded["openWorldHint"] == nil)
}

@Test("MCPToolAnnotations decodes from JSON wire format")
func testMCPToolAnnotationsJSONDecoding() throws {
    let json = """
    {
        "readOnlyHint": true,
        "destructiveHint": true
    }
    """
    let data = json.data(using: .utf8)!

    let annotations = try JSONDecoder().decode(MCPToolAnnotations.self, from: data)

    #expect(annotations.hints.contains(.readOnly))
    #expect(annotations.hints.contains(.destructive))
    #expect(!annotations.hints.contains(.idempotent))
    #expect(!annotations.hints.contains(.openWorld))
}

@Test("MCPToolAnnotations round-trip encoding")
func testMCPToolAnnotationsRoundTrip() throws {
    let original = MCPToolAnnotations(hints: [.readOnly, .idempotent, .openWorld])

    let encoder = JSONEncoder()
    let data = try encoder.encode(original)

    let decoded = try JSONDecoder().decode(MCPToolAnnotations.self, from: data)

    #expect(original == decoded)
    #expect(decoded.hints == original.hints)
}

// MARK: - Tools/List Response Tests

@Test("Tool annotations appear in tools metadata")
func testToolAnnotationsInMetadata() {
    let server = HintsTestServer()
    let tools = server.mcpToolMetadata.convertedToTools()

    // Find the searchItems tool (readOnly)
    guard let searchTool = tools.first(where: { $0.name == "searchItems" }) else {
        #expect(Bool(false), "Could not find searchItems tool")
        return
    }
    #expect(searchTool.annotations != nil)
    #expect(searchTool.annotations?.hints.contains(.readOnly) == true)

    // Find the deleteAccount tool (destructive)
    guard let deleteTool = tools.first(where: { $0.name == "deleteAccount" }) else {
        #expect(Bool(false), "Could not find deleteAccount tool")
        return
    }
    #expect(deleteTool.annotations != nil)
    #expect(deleteTool.annotations?.hints.contains(.destructive) == true)

    // Find the noHints tool (no annotations)
    guard let noHintsTool = tools.first(where: { $0.name == "noHints" }) else {
        #expect(Bool(false), "Could not find noHints tool")
        return
    }
    #expect(noHintsTool.annotations == nil)
}

@Test("Tools with multiple hints preserve all hints")
func testMultipleHintsPreserved() {
    let server = HintsTestServer()
    let tools = server.mcpToolMetadata.convertedToTools()

    // Find the tool with destructive + openWorld
    guard let externalDeleteTool = tools.first(where: { $0.name == "deleteExternalResource" }) else {
        #expect(Bool(false), "Could not find deleteExternalResource tool")
        return
    }
    #expect(externalDeleteTool.annotations?.hints.contains(.destructive) == true)
    #expect(externalDeleteTool.annotations?.hints.contains(.openWorld) == true)

    // Find the tool with all hints
    guard let allHintsTool = tools.first(where: { $0.name == "allHints" }) else {
        #expect(Bool(false), "Could not find allHints tool")
        return
    }
    #expect(allHintsTool.annotations?.hints.contains(.readOnly) == true)
    #expect(allHintsTool.annotations?.hints.contains(.destructive) == true)
    #expect(allHintsTool.annotations?.hints.contains(.idempotent) == true)
    #expect(allHintsTool.annotations?.hints.contains(.openWorld) == true)
}

// MARK: - Computed isConsequential Tests

@Test("computedIsConsequential is false for readOnly only")
func testComputedIsConsequentialReadOnlyOnly() {
    let server = HintsTestServer()

    // Find the searchItems metadata (readOnly)
    guard let searchMeta = server.mcpToolMetadata.first(where: { $0.name == "searchItems" }) else {
        #expect(Bool(false), "Could not find searchItems metadata")
        return
    }

    // readOnly = true, destructive = false -> consequential = false
    #expect(searchMeta.computedIsConsequential == false)
}

@Test("computedIsConsequential is true for destructive")
func testComputedIsConsequentialDestructive() {
    let server = HintsTestServer()

    // Find the deleteAccount metadata (destructive)
    guard let deleteMeta = server.mcpToolMetadata.first(where: { $0.name == "deleteAccount" }) else {
        #expect(Bool(false), "Could not find deleteAccount metadata")
        return
    }

    // readOnly = false, destructive = true -> consequential = true
    #expect(deleteMeta.computedIsConsequential == true)
}

@Test("computedIsConsequential is true for readOnly + destructive combined")
func testComputedIsConsequentialReadOnlyAndDestructive() {
    let server = HintsTestServer()

    // Find the readOnlyWithDestructive metadata
    guard let combinedMeta = server.mcpToolMetadata.first(where: { $0.name == "readOnlyWithDestructive" }) else {
        #expect(Bool(false), "Could not find readOnlyWithDestructive metadata")
        return
    }

    // readOnly = true, destructive = true -> consequential = true (destructive overrides)
    #expect(combinedMeta.computedIsConsequential == true)
}

@Test("computedIsConsequential falls back to isConsequential when no annotations")
func testComputedIsConsequentialFallback() {
    let server = HintsTestServer()

    // Find the noHints metadata (no annotations)
    guard let noHintsMeta = server.mcpToolMetadata.first(where: { $0.name == "noHints" }) else {
        #expect(Bool(false), "Could not find noHints metadata")
        return
    }

    // No annotations, should fall back to legacy isConsequential (default true)
    #expect(noHintsMeta.computedIsConsequential == true)
}

@Test("computedIsConsequential is true for openWorld (no readOnly)")
func testComputedIsConsequentialOpenWorld() {
    let server = HintsTestServer()

    // Find the sendEmail metadata (openWorld)
    guard let emailMeta = server.mcpToolMetadata.first(where: { $0.name == "sendEmail" }) else {
        #expect(Bool(false), "Could not find sendEmail metadata")
        return
    }

    // readOnly = false, destructive = false, openWorld = true -> consequential = true
    #expect(emailMeta.computedIsConsequential == true)
}

@Test("computedIsConsequential is true for idempotent (no readOnly)")
func testComputedIsConsequentialIdempotent() {
    let server = HintsTestServer()

    // Find the updateSetting metadata (idempotent)
    guard let updateMeta = server.mcpToolMetadata.first(where: { $0.name == "updateSetting" }) else {
        #expect(Bool(false), "Could not find updateSetting metadata")
        return
    }

    // readOnly = false, destructive = false, idempotent = true -> consequential = true
    #expect(updateMeta.computedIsConsequential == true)
}

// MARK: - OpenAPI isConsequential Tests

@Test("OpenAPI spec uses computedIsConsequential for readOnly tool")
func testOpenAPIIsConsequentialReadOnly() {
    let server = HintsTestServer()
    let spec = OpenAPISpec(server: server, scheme: "http", host: "localhost:8080")

    // Get the searchItems path
    guard let pathItem = spec.paths["/hintstestserver/searchItems"],
          let operation = pathItem.post else {
        #expect(Bool(false), "Could not find searchItems operation")
        return
    }

    // readOnly tool should have isConsequential = false
    #expect(operation.isConsequential == false)
}

@Test("OpenAPI spec uses computedIsConsequential for destructive tool")
func testOpenAPIIsConsequentialDestructive() {
    let server = HintsTestServer()
    let spec = OpenAPISpec(server: server, scheme: "http", host: "localhost:8080")

    // Get the deleteAccount path
    guard let pathItem = spec.paths["/hintstestserver/deleteAccount"],
          let operation = pathItem.post else {
        #expect(Bool(false), "Could not find deleteAccount operation")
        return
    }

    // destructive tool should have isConsequential = true
    #expect(operation.isConsequential == true)
}

@Test("OpenAPI spec uses computedIsConsequential for combined readOnly+destructive")
func testOpenAPIIsConsequentialCombined() {
    let server = HintsTestServer()
    let spec = OpenAPISpec(server: server, scheme: "http", host: "localhost:8080")

    // Get the readOnlyWithDestructive path
    guard let pathItem = spec.paths["/hintstestserver/readOnlyWithDestructive"],
          let operation = pathItem.post else {
        #expect(Bool(false), "Could not find readOnlyWithDestructive operation")
        return
    }

    // combined readOnly + destructive should have isConsequential = true
    #expect(operation.isConsequential == true)
}
