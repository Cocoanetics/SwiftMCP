import Testing
import SwiftMCP
import SwiftMCPUtilityCore

@Suite("Proxy Generator OpenAPI Tests", .tags(.proxyGenerator))
struct ProxyGeneratorOpenAPITests {
    @Test("OpenAPI object responses generate Codable structs")
    func openAPIObjectResponseGeneratesStruct() throws {
        let tool = MCPTool(name: "currentWeather", description: nil, inputSchema: .object(.init(properties: [:], required: [])))
        let responseSchema = JSONSchema.object(.init(
            properties: [
                "temperature": .number(title: nil, description: "Current temperature", minimum: nil, maximum: nil),
                "condition": .string(title: nil, description: "Weather condition", format: nil, minLength: nil, maxLength: nil)
            ],
            required: ["temperature"],
            description: "Weather response"
        ))

        let returnInfo = OpenAPIReturnInfo(typeName: "String", schema: responseSchema, description: "A structured response")
        let source = ProxyGenerator.generate(
            typeName: "WeatherProxy",
            tools: [tool],
            openapiReturnSchemas: ["currentWeather": returnInfo]
        ).description

        #expect(source.contains("public struct CurrentWeatherResponse"))
        #expect(source.contains("public let temperature: Double"))
        #expect(source.contains("public let condition: String?"))
        #expect(source.contains("public func currentWeather() async throws -> CurrentWeatherResponse"))
        #expect(source.contains("MCPClientResultDecoder.decode(CurrentWeatherResponse.self"))
    }

    @Test("Tool output schemas generate Codable structs")
    func outputSchemaObjectResponseGeneratesStruct() throws {
        let outputSchema = JSONSchema.object(.init(
            properties: [
                "temperature": .number(title: nil, description: "Current temperature", minimum: nil, maximum: nil),
                "condition": .string(title: nil, description: "Weather condition", format: nil, minLength: nil, maxLength: nil)
            ],
            required: [],
            description: "Weather response"
        ))
        let tool = MCPTool(
            name: "currentWeather",
            description: nil,
            inputSchema: .object(.init(properties: [:], required: [])),
            outputSchema: outputSchema
        )

        let source = ProxyGenerator.generate(
            typeName: "WeatherProxy",
            tools: [tool]
        ).description

        #expect(source.contains("public struct CurrentWeatherResponse"))
        #expect(source.contains("public let temperature: Double?"))
        #expect(source.contains("public let condition: String?"))
        #expect(source.contains("public func currentWeather() async throws -> CurrentWeatherResponse"))
    }

    @Test("OpenAPI enum responses generate string enums")
    func openAPIEnumResponseGeneratesEnum() throws {
        let tool = MCPTool(name: "createEvent", description: nil, inputSchema: .object(.init(properties: [:], required: [])))
        let responseSchema = JSONSchema.enum(values: ["busy", "free", "tentative"], title: nil, description: "Availability", enumNames: nil)

        let returnInfo = OpenAPIReturnInfo(typeName: "String", schema: responseSchema, description: "Availability result")
        let source = ProxyGenerator.generate(
            typeName: "EventProxy",
            tools: [tool],
            openapiReturnSchemas: ["createEvent": returnInfo]
        ).description

        #expect(source.contains("public enum CreateEventResponse"))
        #expect(source.contains("case busy = \"busy\""))
        #expect(source.contains("case free = \"free\""))
        #expect(source.contains("case tentative = \"tentative\""))
        #expect(source.contains("public func createEvent() async throws -> CreateEventResponse"))
    }

    @Test("OpenAPI date-time returns map to Date")
    func openAPIDateReturnMapsToDate() throws {
        let tool = MCPTool(name: "getUserContext", description: nil, inputSchema: .object(.init(properties: [:], required: [])))
        let responseSchema = JSONSchema.string(title: nil, description: "User time", format: "date-time", minLength: nil, maxLength: nil)

        let returnInfo = OpenAPIReturnInfo(typeName: "String", schema: responseSchema, description: "User time")
        let source = ProxyGenerator.generate(
            typeName: "ContextProxy",
            tools: [tool],
            openapiReturnSchemas: ["getUserContext": returnInfo]
        ).description

        #expect(source.contains("public func getUserContext() async throws -> Date"))
        #expect(source.contains("MCPClientResultDecoder.decode(Date.self"))
    }

    @Test("Object with single array key returns array type directly")
    func objectWithSingleArrayKeyReturnsArrayType() throws {
        let tool = MCPTool(name: "getItems", description: nil, inputSchema: .object(.init(properties: [:], required: [])))
        let responseSchema = JSONSchema.object(.init(
            properties: [
                "items": .array(
                    items: .string(title: nil, description: "Item name", format: nil, minLength: nil, maxLength: nil),
                    title: nil,
                    description: "List of items",
                    defaultValue: nil
                )
            ],
            required: [],
            description: "Items response"
        ))

        let returnInfo = OpenAPIReturnInfo(typeName: "String", schema: responseSchema, description: "A list of items")
        let source = ProxyGenerator.generate(
            typeName: "ItemsProxy",
            tools: [tool],
            openapiReturnSchemas: ["getItems": returnInfo]
        ).description

        // Should return array type directly, not a wrapper struct
        #expect(source.contains("public func getItems() async throws -> [String]"))
        #expect(source.contains("MCPClientResultDecoder.decode([String].self"))
        // Should NOT create a wrapper struct
        #expect(!source.contains("public struct GetItemsResponse"))
    }
}

extension Tag {
    @Tag static var proxyGenerator: Self
}
