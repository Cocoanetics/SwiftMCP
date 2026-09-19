import Foundation
import Testing
@testable import SwiftMCP
@testable import SwiftMCPUtilityCore

@Schema
struct RideRecord: Sendable, Codable, Equatable {
    let id: String
    let riderId: String?
}

@MCPServer(name: "Structured Fixture")
final class StructuredFixtureServer: Sendable {
    /// The ride in progress.
    @MCPTool
    func currentRide() -> RideRecord {
        RideRecord(id: "r-42", riderId: "elise")
    }

    /// Every ride, wrapped by the server as `{"items": [...]}`.
    @MCPTool
    func allRides() -> [RideRecord] {
        [RideRecord(id: "r-1", riderId: nil), RideRecord(id: "r-2", riderId: "erika")]
    }
}

@Suite("Structured tool results")
struct StructuredToolResultTests {

    private func textBlock(_ json: String) -> JSONValue {
        .object(["type": .string("text"), "text": .string(json)])
    }

    // MARK: - Decoding from a JSONValue

    @Test("decodes a struct straight from structuredContent")
    func decodesFromJSONValue() throws {
        let value: JSONValue = .object(["id": .string("r1"), "riderId": .string("elise")])
        let decoded = try MCPClientResultDecoder.decode(RideRecord.self, from: value)
        #expect(decoded == RideRecord(id: "r1", riderId: "elise"))
    }

    @Test("unwraps a single-key object, as the text path does")
    func unwrapsSingleKey() throws {
        let value: JSONValue = .object(["rides": .array([.object(["id": .string("r1")])])])
        #expect(try MCPClientResultDecoder.decode([RideRecord].self, from: value).map(\.id) == ["r1"])
    }

    @Test("an explicit null and an absent key both decode as nil")
    func nullIsNil() throws {
        let explicit: JSONValue = .object(["id": .string("r1"), "riderId": .null])
        let absent: JSONValue = .object(["id": .string("r1")])
        #expect(try MCPClientResultDecoder.decode(RideRecord.self, from: explicit).riderId == nil)
        #expect(try MCPClientResultDecoder.decode(RideRecord.self, from: absent).riderId == nil)
    }

    // MARK: - Which source a typed call uses

    @Test("structuredContent wins over the text block")
    func structuredWins() async throws {
        let proxy = MCPServerProxy(config: .stdioHandles(server: StructuredFixtureServer()))
        let result = MCPToolCallResult(
            content: [textBlock(#"{"id":"from-text"}"#)],
            structuredContent: .object(["id": .string("from-structured")])
        )
        #expect(try await proxy.decode(RideRecord.self, from: result).id == "from-structured")
    }

    @Test("the text block is the fallback when there is nothing structured")
    func textFallback() async throws {
        let proxy = MCPServerProxy(config: .stdioHandles(server: StructuredFixtureServer()))
        let result = MCPToolCallResult(content: [textBlock(#"{"id":"from-text"}"#)])
        #expect(try await proxy.decode(RideRecord.self, from: result).id == "from-text")
    }

    // MARK: - End to end, in process

    @Test("a struct-returning tool arrives structured and decodes typed")
    func endToEndStruct() async throws {
        let proxy = MCPServerProxy(config: .stdioHandles(server: StructuredFixtureServer()))
        try await proxy.connect()
        defer { Task { await proxy.disconnect() } }

        let result = try await proxy.callToolResult("currentRide")
        #expect(result.structuredContent != nil, "the server negotiates a version that sends structuredContent")
        #expect(result.content.count == 1, "and still sends the text block for readers")

        let ride = try await proxy.callTool("currentRide", as: RideRecord.self)
        #expect(ride == RideRecord(id: "r-42", riderId: "elise"))

        // The String form is unchanged.
        let text = try await proxy.callTool("currentRide")
        #expect(text.contains("r-42"))
    }

    @Test("an array return comes through the server's items wrapper")
    func endToEndArray() async throws {
        let proxy = MCPServerProxy(config: .stdioHandles(server: StructuredFixtureServer()))
        try await proxy.connect()
        defer { Task { await proxy.disconnect() } }

        let rides = try await proxy.callTool("allRides", as: [RideRecord].self)
        #expect(rides.map(\.id) == ["r-1", "r-2"])
        #expect(rides[0].riderId == nil)
    }

    // MARK: - What the generator emits

    private func tool(_ name: String, output: JSONSchema?) -> MCPTool {
        MCPTool(
            name: name, description: nil,
            inputSchema: .object(.init(properties: ["q": .string(title: nil, description: nil)], required: ["q"])),
            outputSchema: output
        )
    }

    @Test("a schema-typed return calls the typed overload")
    func generatorEmitsTypedCall() throws {
        let ride: JSONSchema = .object(.init(
            properties: ["id": .string(title: nil, description: nil)], required: ["id"], title: "Ride"
        ))
        let source = ProxyGenerator.generate(
            typeName: "P",
            tools: [tool("get_ride", output: .object(.init(properties: ["ride": ride], required: ["ride"])))]
        ).description
        #expect(source.contains(
            "return try await proxy.callTool(\"get_ride\", arguments: arguments, as: GetRideResponse.self)"
        ))
        #expect(!source.contains("MCPClientResultDecoder"))
    }

    @Test("a text return keeps the text path")
    func generatorKeepsTextPath() throws {
        let source = ProxyGenerator.generate(typeName: "P", tools: [tool("echo", output: nil)]).description
        #expect(source.contains("let text = try await proxy.callTool(\"echo\", arguments: arguments)"))
        #expect(source.contains("return text"))
    }

    @Test("content types stay on the text path, structured or not")
    func contentTypesStayOnText() {
        #expect(!ProxyGenerator.decodesStructured("MCPImage"))
        #expect(!ProxyGenerator.decodesStructured("[MCPText]"))
        #expect(!ProxyGenerator.decodesStructured("Data"))
        #expect(ProxyGenerator.decodesStructured("[Ride]"))
        #expect(ProxyGenerator.decodesStructured("Ride?"))
        #expect(ProxyGenerator.decodesStructured("[String]"))
        #expect(!ProxyGenerator.decodesStructured("String"))
    }
}
