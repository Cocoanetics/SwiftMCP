import Testing
import SwiftMCP
import SwiftMCPUtilityCore

@Suite("Proxy Generator Parameter Naming Tests", .tags(.proxyGenerator))
struct ProxyGeneratorParameterNamingTests {

    private func makeTool(properties: [String: JSONSchema], required: Set<String>) -> MCPTool {
        MCPTool(
            name: "accept_ride",
            description: nil,
            inputSchema: .object(.init(properties: properties, required: required))
        )
    }

    private func acceptRideTool() -> MCPTool {
        makeTool(
            properties: [
                "ride_id": .string(title: nil, description: nil),
                "push_destination": .boolean(title: nil, description: nil)
            ],
            required: ["ride_id"]
        )
    }

    private func generate(_ naming: ProxyGenerator.ParameterNaming?) -> String {
        if let naming {
            return ProxyGenerator.generate(
                typeName: "NamingProxy",
                tools: [acceptRideTool()],
                parameterNaming: naming
            ).description
        }
        return ProxyGenerator.generate(
            typeName: "NamingProxy",
            tools: [acceptRideTool()]
        ).description
    }

    @Test("Parameter labels keep the server's spelling by default")
    func defaultsToVerbatim() throws {
        let source = generate(nil)
        #expect(source.contains("push_destination: Bool? = nil"))
        #expect(source.contains("ride_id: String"))
        #expect(!source.contains("rideId"))
    }

    @Test("lowerCamelCase renames parameter labels but not wire keys")
    func lowerCamelCaseRenamesLabelsOnly() throws {
        let source = generate(.lowerCamelCase)
        #expect(source.contains("rideId: String"))
        #expect(source.contains("pushDestination: Bool? = nil"))
        // The JSON argument keys must stay exactly as the server declared them.
        #expect(source.contains("arguments[\"ride_id\"] = try MCPClientArgumentEncoder.encode(rideId)"))
        #expect(source.contains("arguments[\"push_destination\"]"))
        #expect(!source.contains("arguments[\"rideId\"]"))
    }

    @Test("snakeCase renames camelCased parameter labels")
    func snakeCaseRenamesLabels() throws {
        let tool = makeTool(
            properties: ["rideId": .string(title: nil, description: nil)],
            required: ["rideId"]
        )
        let source = ProxyGenerator.generate(
            typeName: "NamingProxy",
            tools: [tool],
            parameterNaming: .snakeCase
        ).description

        #expect(source.contains("ride_id: String"))
        #expect(source.contains("arguments[\"rideId\"] = try MCPClientArgumentEncoder.encode(ride_id)"))
    }

    @Test("Function naming is independent of parameter naming")
    func functionNamingIsOrthogonal() throws {
        let source = ProxyGenerator.generate(
            typeName: "NamingProxy",
            tools: [acceptRideTool()],
            functionNaming: .verbatim,
            parameterNaming: .lowerCamelCase
        ).description

        #expect(source.contains("public func accept_ride("))
        #expect(source.contains("rideId: String"))
    }

    @Test("A renaming collision keeps the server's spelling")
    func collidingNamesFallBackToVerbatim() throws {
        let tool = makeTool(
            properties: [
                "ride_id": .string(title: nil, description: nil),
                "rideId": .string(title: nil, description: nil)
            ],
            required: ["ride_id", "rideId"]
        )
        let source = ProxyGenerator.generate(
            typeName: "NamingProxy",
            tools: [tool],
            parameterNaming: .lowerCamelCase
        ).description

        // Both parameters survive, and both wire keys are still sent.
        #expect(source.contains("ride_id: String"))
        #expect(source.contains("rideId: String"))
        #expect(source.contains("arguments[\"ride_id\"]"))
        #expect(source.contains("arguments[\"rideId\"]"))
    }
}
