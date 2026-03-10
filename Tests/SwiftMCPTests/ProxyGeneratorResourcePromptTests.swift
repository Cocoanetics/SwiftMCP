import Foundation
import Testing
import SwiftMCP
import SwiftMCPUtilityCore

@Suite("Proxy Generator Resource/Prompt Tests", .tags(.proxyGenerator))
struct ProxyGeneratorResourcePromptTests {
    @Test("Generator emits resource and prompt convenience wrappers")
    func generatorEmitsResourceAndPromptWrappers() throws {
        let source = ProxyGenerator.generate(
            typeName: "DemoProxy",
            tools: [],
            resources: [
                SimpleResource(
                    uri: URL(string: "config://app")!,
                    name: "config",
                    description: "Reads the app configuration"
                )
            ],
            resourceTemplates: [
                SimpleResourceTemplate(
                    uriTemplate: "users://{user_id}/profile/localized?locale={lang}",
                    name: "userProfile",
                    description: "Reads a user profile"
                )
            ],
            prompts: [
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
        ).description

        #expect(source.contains("public func listResources() async throws -> [SimpleResource]"))
        #expect(source.contains("public func listResourceTemplates() async throws -> [SimpleResourceTemplate]"))
        #expect(source.contains("public func readResource(uri: URL) async throws -> [GenericResourceContent]"))
        #expect(source.contains("public func config() async throws -> [GenericResourceContent]"))
        #expect(source.contains("public func userProfile(user_id: String, lang: String? = nil) async throws -> [GenericResourceContent]"))
        #expect(source.contains("let uri = try \"users://{user_id}/profile/localized?locale={lang}\".constructURI(with: uriParameters)"))
        #expect(source.contains("public func listPrompts() async throws -> [Prompt]"))
        #expect(source.contains("public func getPrompt(name: String, arguments: [String: any Sendable] = [:]) async throws -> PromptResult"))
        #expect(source.contains("public func helloPrompt(name: String, excited: Bool? = nil) async throws -> PromptResult"))
        #expect(source.contains("arguments[\"excited\"] = MCPClientArgumentEncoder.encode(excited)"))
    }

    @Test("Generator keeps distinct resource templates even when names collide")
    func generatorKeepsDistinctResourceTemplatesWithSameName() throws {
        let source = ProxyGenerator.generate(
            typeName: "DemoProxy",
            tools: [],
            resourceTemplates: [
                SimpleResourceTemplate(
                    uriTemplate: "users://{user_id}/profile",
                    name: "userProfile",
                    description: "Default profile"
                ),
                SimpleResourceTemplate(
                    uriTemplate: "users://{user_id}/profile/localized?locale={lang}",
                    name: "userProfile",
                    description: "Localized profile"
                )
            ],
            supportsResources: true
        ).description

        #expect(source.contains("public func userProfile(user_id: String) async throws -> [GenericResourceContent]"))
        #expect(source.contains("public func userProfileResource(user_id: String, lang: String? = nil) async throws -> [GenericResourceContent]"))
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
        #expect(source.contains("public func getPrompt(name: String, arguments: [String: any Sendable] = [:]) async throws -> PromptResult"))
    }
}
