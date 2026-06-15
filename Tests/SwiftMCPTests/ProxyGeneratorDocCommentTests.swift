import Testing
import SwiftMCP
import SwiftMCPUtilityCore

@Suite("Proxy Generator Doc Comment Tests", .tags(.proxyGenerator))
struct ProxyGeneratorDocCommentTests {
    @Test("Type doc comment includes server description lines")
    func typeDocCommentIncludesDescription() throws {
        let metadata = ProxyGenerator.HeaderMetadata(
            fileName: "CalculatorProxy.swift",
            serverName: "Calculator",
            serverVersion: "1.0",
            serverDescription: "Line one.\n\nLine \"two\".\nLine three.",
            source: nil,
            openAPI: nil
        )

        let source = ProxyGenerator.generate(
            typeName: "CalculatorProxy",
            tools: [],
            headerMetadata: metadata
        ).description

        #expect(source.contains("/// Line one."))
        #expect(source.contains("/// Line \"two\"."))
        #expect(source.contains("/// Line three."))
    }

    @Test("Metadata section embeds title, websiteUrl and icon URLs")
    func metadataSectionEmbedsServerIdentity() throws {
        let metadata = ProxyGenerator.HeaderMetadata(
            fileName: "WeatherProxy.swift",
            serverName: "weather",
            serverVersion: "1.0",
            serverDescription: nil,
            source: nil,
            openAPI: nil,
            serverTitle: "Weather Tools",
            serverWebsiteUrl: "https://example.com/weather",
            serverIconURLs: ["https://example.com/icon.png"]
        )

        let source = ProxyGenerator.generate(
            typeName: "WeatherProxy",
            tools: [],
            headerMetadata: metadata
        ).description

        #expect(source.contains(#"public static let serverTitle: String? = "Weather Tools""#))
        #expect(source.contains(#"public static let serverWebsiteUrl: String? = "https://example.com/weather""#))
        #expect(source.contains(#"public static let serverIconURLs: [String] = ["https://example.com/icon.png"]"#))
        // The type doc comment prefers the title over the programmatic name.
        #expect(source.contains("A generated proxy for the Weather Tools MCP server (1.0)."))
    }

    @Test("Server titles with special characters are escaped in the generated literal")
    func escapesSpecialCharactersInTitle() throws {
        let metadata = ProxyGenerator.HeaderMetadata(
            fileName: "P.swift",
            serverName: "p",
            serverVersion: "1.0",
            serverDescription: nil,
            source: nil,
            openAPI: nil,
            serverTitle: "a\"b\\c\nd"   // quote, backslash, newline
        )

        let source = ProxyGenerator.generate(
            typeName: "P",
            tools: [],
            headerMetadata: metadata
        ).description

        // " -> \", \ -> \\, newline -> \n : a valid Swift literal, not a malformed one.
        #expect(source.contains(#"a\"b\\c\nd"#))
    }
}
