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

        #expect(source.contains("/**"))
        #expect(source.contains("Line one."))
        #expect(source.contains("Line \"two\"."))
        #expect(source.contains("Line three."))
        #expect(source.contains("*/"))
    }
}
