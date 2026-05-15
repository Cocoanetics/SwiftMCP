import Foundation
import Testing
import SwiftMCP
import SwiftMCPUtilityCore

@Suite("Proxy Generator Resource/Prompt Tests", .tags(.proxyGenerator))
struct ProxyGeneratorResourcePromptTests {

    private func makeDemoResources() -> [SimpleResource] {
        [
            SimpleResource(
                uri: URL(string: "config://app")!,
                name: "config",
                description: "Reads the app configuration"
            )
        ]
    }

    private func makeDemoResourceTemplates() -> [SimpleResourceTemplate] {
        [
            SimpleResourceTemplate(
                uriTemplate: "users://{user_id}/profile/localized?locale={lang}",
                name: "userProfile",
                description: "Reads a user profile"
            )
        ]
    }

    private func makeDemoPrompts() -> [Prompt] {
        [
            Prompt(
                name: "helloPrompt",
                description: "Greets the user",
                arguments: [
                    MCPParameterInfo(
                        name: "name",
                        type: String.self,
                        description: "Name to greet",
                        isRequired: true
                    ),
                    MCPParameterInfo(
                        name: "excited",
                        type: Bool.self,
                        description: "Whether to add emphasis",
                        isRequired: false
                    )
                ]
            )
        ]
    }

    @Test("Generator emits standard resource and prompt helpers only")
    func generatorEmitsStandardResourceAndPromptHelpers() throws {
        let source = ProxyGenerator.generate(
            typeName: "DemoProxy",
            tools: [],
            resources: makeDemoResources(),
            resourceTemplates: makeDemoResourceTemplates(),
            prompts: makeDemoPrompts()
        ).description

        #expect(source.contains("public func listResources() async throws -> [SimpleResource]"))
        #expect(source.contains("public func listResourceTemplates() async throws -> [SimpleResourceTemplate]"))
        #expect(source.contains("public func readResource(uri: URL) async throws -> [GenericResourceContent]"))
        #expect(source.contains("public func listPrompts() async throws -> [Prompt]"))
        let getPromptSignature = "public func getPrompt(name: String, arguments: JSONDictionary = [:])"
            + " async throws -> PromptResult"
        #expect(source.contains(getPromptSignature))
        #expect(!source.contains("public func config() async throws -> [GenericResourceContent]"))
        let userProfileSignature = "public func userProfile(user_id: String, lang: String? = nil)"
            + " async throws -> [GenericResourceContent]"
        #expect(!source.contains(userProfileSignature))
        let helloPromptSignature = "public func helloPrompt(name: String, excited: Bool? = nil)"
            + " async throws -> PromptResult"
        #expect(!source.contains(helloPromptSignature))
    }

    @Test("Generator emits generic resource and prompt helpers from capability flags")
    func generatorEmitsSurfaceHelpersFromCapabilities() throws {
        let source = ProxyGenerator.generate(
            typeName: "DemoProxy",
            tools: [],
            supportsResources: true,
            supportsPrompts: true
        ).description

        #expect(source.contains("// MARK: - Resources"))
        #expect(source.contains("public func listResources() async throws -> [SimpleResource]"))
        #expect(source.contains("public func readResource(uri: URL) async throws -> [GenericResourceContent]"))
        #expect(source.contains("// MARK: - Prompts"))
        #expect(source.contains("public func listPrompts() async throws -> [Prompt]"))
        let getPromptSignature2 = "public func getPrompt(name: String, arguments: JSONDictionary = [:])"
            + " async throws -> PromptResult"
        #expect(source.contains(getPromptSignature2))
    }
}
