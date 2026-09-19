import Testing
import SwiftMCP
import SwiftMCPUtilityCore

@Suite("Proxy Generator Titled Type Tests", .tags(.proxyGenerator))
struct ProxyGeneratorTitledTypeTests {

    private let emptyInput: JSONSchema = .object(.init(properties: [:], required: []))

    private func ride(title: String? = "Ride", extra: [String: JSONSchema] = [:]) -> JSONSchema {
        var properties: [String: JSONSchema] = [
            "id": .string(title: nil, description: nil),
            "rider_id": .string(title: nil, description: nil)
        ]
        properties.merge(extra) { _, new in new }
        return .object(.init(properties: properties, required: ["id", "rider_id"], title: title))
    }

    private func tool(_ name: String, output: JSONSchema) -> MCPTool {
        MCPTool(name: name, description: nil, inputSchema: emptyInput, outputSchema: output)
    }

    @Test("A titled output schema names its own type")
    func titleNamesTheType() throws {
        let tools = [tool("get_ride", output: .object(.init(properties: ["ride": ride()], required: ["ride"])))]
        let source = ProxyGenerator.generate(typeName: "P", tools: tools).description
        let camel = ProxyGenerator.generate(typeName: "P", tools: tools, parameterNaming: .lowerCamelCase).description

        #expect(source.contains("public struct Ride: Codable, Sendable, Hashable"))
        #expect(!source.contains("GetRideResponseRide"))
        // Property spelling follows --parameter-naming; the wire key stays in CodingKeys.
        #expect(source.contains("public let rider_id: String"))
        #expect(camel.contains("public let riderId: String"))
        #expect(camel.contains("case riderId = \"rider_id\""))
    }

    @Test("The same title over the same shape is one type across tools")
    func sameTitleSameShapeIsShared() throws {
        let source = ProxyGenerator.generate(
            typeName: "P",
            tools: [
                tool("list_rides", output: .object(.init(
                    properties: ["rides": .array(items: ride())], required: ["rides"]
                ))),
                tool("get_ride", output: .object(.init(properties: ["ride": ride()], required: ["ride"]))),
                tool("save_ride", output: ride())
            ]
        ).description

        #expect(source.components(separatedBy: "public struct Ride:").count == 2, "exactly one Ride")
        #expect(source.contains("async throws -> [Ride]"))
        #expect(source.contains("async throws -> Ride {"))
        #expect(!source.contains("Ride2"))
    }

    @Test("The same title over a different shape gets its own name")
    func sameTitleDifferentShapeIsSplit() throws {
        let source = ProxyGenerator.generate(
            typeName: "P",
            tools: [
                tool("get_ride", output: .object(.init(properties: ["ride": ride()], required: ["ride"]))),
                tool("get_other", output: .object(.init(
                    properties: ["ride": ride(extra: ["state": .string(title: nil, description: nil)])],
                    required: ["ride"]
                )))
            ]
        ).description

        #expect(source.contains("public struct Ride:"))
        #expect(source.contains("public struct Ride2:"))
        #expect(source.contains("public let state: String?"))
    }

    @Test("The same shape documented two ways is still one type")
    func descriptionsDoNotSplitAType() throws {
        let documented: JSONSchema = .object(.init(
            properties: [
                "id": .string(title: nil, description: "the ride's id"),
                "rider_id": .string(title: nil, description: nil)
            ],
            required: ["id", "rider_id"], title: "Ride", description: "a ride"
        ))
        let rephrased: JSONSchema = .object(.init(
            properties: [
                "id": .string(title: nil, description: "an identifier"),
                "rider_id": .string(title: nil, description: nil)
            ],
            required: ["id", "rider_id"], title: "Ride"
        ))
        let source = ProxyGenerator.generate(
            typeName: "P",
            tools: [
                tool("get_ride", output: .object(.init(properties: ["ride": documented], required: ["ride"]))),
                tool("save_ride", output: rephrased)
            ]
        ).description

        #expect(source.components(separatedBy: "public struct Ride:").count == 2, "exactly one Ride")
        #expect(!source.contains("Ride2"))
    }

    @Test("The same shape with required listed in another order is still one type")
    func requiredOrderDoesNotSplitAType() throws {
        let one: JSONSchema = .object(.init(
            properties: [
                "id": .string(title: nil, description: nil),
                "rider_id": .string(title: nil, description: nil)
            ],
            required: ["id", "rider_id"], title: "Ride"
        ))
        let other: JSONSchema = .object(.init(
            properties: [
                "id": .string(title: nil, description: nil),
                "rider_id": .string(title: nil, description: nil)
            ],
            required: ["rider_id", "id"], title: "Ride"
        ))
        let source = ProxyGenerator.generate(
            typeName: "P",
            tools: [
                tool("get_ride", output: .object(.init(properties: ["ride": one], required: ["ride"]))),
                tool("save_ride", output: other)
            ]
        ).description

        #expect(source.components(separatedBy: "public struct Ride:").count == 2, "exactly one Ride")
        #expect(!source.contains("Ride2"))
    }

    @Test("A titled single-key object stays a struct")
    func titledSingleKeyObjectIsNotFlattened() throws {
        let upcoming: JSONSchema = .object(.init(
            properties: ["rides": .array(items: ride())], required: ["rides"], title: "Upcoming"
        ))
        let source = ProxyGenerator.generate(
            typeName: "P", tools: [tool("upcoming", output: upcoming)]
        ).description

        #expect(source.contains("public struct Upcoming:"))
        #expect(source.contains("async throws -> Upcoming {"))
    }

    @Test("Untitled schemas keep their positional names")
    func untitledKeepsPositionalNames() throws {
        let source = ProxyGenerator.generate(
            typeName: "P",
            tools: [tool("get_ride", output: .object(.init(
                properties: ["ride": ride(title: nil)], required: ["ride"]
            )))]
        ).description

        #expect(source.contains("public struct GetRideResponseRide:"))
        #expect(!source.contains("public struct Ride:"))
    }
}
