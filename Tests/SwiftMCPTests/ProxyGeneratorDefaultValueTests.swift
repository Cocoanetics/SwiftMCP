import Testing
import AnyCodable
import SwiftMCP
import SwiftMCPUtilityCore

@Suite("Proxy Generator Default Value Tests", .tags(.proxyGenerator))
struct ProxyGeneratorDefaultValueTests {
    @Test("Default values appear in generated signatures")
    func proxyGeneratorIncludesDefaultValues() throws {
        let schema = JSONSchema.object(.init(
            properties: [
                "requiredValue": .number(title: nil, description: nil, minimum: nil, maximum: nil),
                "optionalValue": .number(title: nil, description: nil, minimum: nil, maximum: nil),
                "defaultValue": .number(
                    title: nil,
                    description: nil,
                    minimum: nil,
                    maximum: nil,
                    defaultValue: AnyCodable(5)
                ),
                "dateDefault": .string(
                    title: nil,
                    description: nil,
                    format: "date-time",
                    minLength: nil,
                    maxLength: nil,
                    defaultValue: AnyCodable("2024-01-02T03:04:05Z")
                ),
                "urlDefault": .string(
                    title: nil,
                    description: nil,
                    format: "uri",
                    minLength: nil,
                    maxLength: nil,
                    defaultValue: AnyCodable("https://example.com")
                ),
                "arrayDefault": .array(
                    items: .number(title: nil, description: nil, minimum: nil, maximum: nil),
                    title: nil,
                    description: nil,
                    defaultValue: AnyCodable([1, 2, 3])
                ),
                "enumDefault": .enum(
                    values: ["one", "two"],
                    title: nil,
                    description: nil,
                    enumNames: nil,
                    defaultValue: AnyCodable("one")
                )
            ],
            required: ["requiredValue"]
        ))
        let tool = MCPTool(name: "defaultsTest", description: nil, inputSchema: schema)

        let source = ProxyGenerator.generate(
            typeName: "DefaultsProxy",
            tools: [tool]
        ).description

        #expect(source.contains("public func defaultsTest("))
        #expect(source.contains("requiredValue: Double"))
        #expect(source.contains("optionalValue: Double? = nil"))
        #expect(source.contains("defaultValue: Double = 5"))
        #expect(source.contains("dateDefault: Date = ISO8601DateFormatter().date(from: \"2024-01-02T03:04:05Z\")!"))
        #expect(source.contains("urlDefault: URL = URL(string: \"https://example.com\")!"))
        #expect(source.contains("arrayDefault: [Double] = [1, 2, 3]"))
        #expect(source.contains("enumDefault: String = \"one\""))
    }
}
