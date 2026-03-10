import Foundation
import Testing
import SwiftMCP
import SwiftMCPUtilityCore

@Suite("Proxy Generator Resource/Prompt Tests", .tags(.proxyGenerator))
struct ProxyGeneratorResourcePromptTests {
    @Test("Generator emits resource and prompt wrappers when surfaces are present")
    func generatorEmitsResourceAndPromptWrappers() throws {
        let source = ProxyGenerator.generate(
            typeName: "DemoProxy",
            tools: [],
            resources: [SimpleResource(uri: URL(string: "config://app")!, name: "config")],
            resourceTemplates: [SimpleResourceTemplate(uriTemplate: "users://{user_id}/profile", name: "userProfile")],
            prompts: [
                Prompt(
                    name: "helloPrompt",
                    description: "Greets the user",
                    arguments: [MCPParameterInfo(name: "name", type: String.self, isRequired: true)]
                )
            ]
        ).description

        #expect(source.contains("public func listResources() async throws -> [SimpleResource]"))
        #expect(source.contains("public func listResourceTemplates() async throws -> [SimpleResourceTemplate]"))
        #expect(source.contains("public func readResource(uri: URL) async throws -> [GenericResourceContent]"))
        #expect(source.contains("public func listPrompts() async throws -> [Prompt]"))
        #expect(source.contains("public func getPrompt(name: String, arguments: [String: any Sendable] = [:]) async throws -> PromptResult"))
    }
}
