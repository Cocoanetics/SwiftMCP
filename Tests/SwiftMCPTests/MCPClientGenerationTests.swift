import Foundation
import Testing
import SwiftMCP

@Schema
struct ClientPayload: Codable, Sendable {
    let count: Int
    let label: String
}

@Schema
struct ClientResult: Codable, Sendable {
    let total: Int
    let status: String
}

enum ClientInputEnum: CaseIterable, Sendable {
    case alpha
    case beta
}

enum ClientOutputEnum: String, CaseIterable, Codable, Sendable {
    case one
    case two
}

@MCPServer(generateClient: true)
actor ClientTestServer {
    var lastMessage: String?

    /// Adds two integers.
    /// - Parameter a: First value.
    /// - Parameter b: Second value.
    /// - Returns: The sum.
    @MCPTool
    func addInts(a: Int, b: Int) -> Int {
        a + b
    }

    /// Adds two doubles asynchronously.
    /// - Parameter a: First value.
    /// - Parameter b: Second value.
    /// - Returns: The sum.
    @MCPTool
    func addDoubles(a: Double, b: Double) async -> Double {
        a + b
    }

    /// Multiplies with a default multiplier.
    /// - Parameter a: Base value.
    /// - Parameter b: Multiplier.
    /// - Returns: The product.
    @MCPTool
    func multiply(a: Int, b: Int = 2) -> Int {
        a * b
    }

    /// Echoes an enum input.
    /// - Parameter value: Enum value to echo.
    /// - Returns: The case label.
    @MCPTool
    func echoEnum(value: ClientInputEnum) -> String {
        String(describing: value)
    }

    /// Joins enum values.
    /// - Parameter values: Enum values to join.
    /// - Returns: Comma-separated case labels.
    @MCPTool
    func joinEnums(values: [ClientInputEnum]) -> String {
        values.map { String(describing: $0) }.joined(separator: ",")
    }

    /// Describes an optional enum.
    /// - Parameter value: Optional enum value.
    /// - Returns: The case label or "none".
    @MCPTool
    func describeEnum(value: ClientInputEnum? = nil) -> String {
        value.map { String(describing: $0) } ?? "none"
    }

    /// Returns an enum value.
    /// - Parameter flag: Toggle output.
    /// - Returns: A client output enum.
    @MCPTool
    func makeEnum(flag: Bool) -> ClientOutputEnum {
        flag ? .one : .two
    }

    /// Wraps a payload into a result.
    /// - Parameter payload: The payload to wrap.
    /// - Returns: The result.
    @MCPTool
    func wrap(payload: ClientPayload) -> ClientResult {
        ClientResult(total: payload.count, status: payload.label)
    }

    /// Records a message.
    /// - Parameter message: Message to store.
    @MCPTool
    func record(message: String) {
        lastMessage = message
    }

    /// Returns a profile string as a resource.
    /// - Parameter user_id: The user identifier.
    /// - Returns: A user profile summary.
    @MCPResource("users://{user_id}/profile")
    func userProfile(user_id: Int) async -> String {
        "Profile \(user_id)"
    }

    /// Returns structured resource data.
    /// - Returns: A structured resource payload.
    @MCPResource("app://summary")
    func summaryResource() async -> ClientResult {
        ClientResult(total: 8, status: "ready")
    }

    /// Returns profile text via multiple URI templates.
    /// - Parameter user_id: The user identifier.
    /// - Parameter lang: Optional language code.
    /// - Returns: A localized user profile summary.
    @MCPResource(["users://{user_id}/profile", "users://{user_id}/profile/localized?lang={lang}"])
    func versionedUserProfile(user_id: Int, lang: String? = nil) async -> String {
        if let lang {
            return "Profile \(user_id) [\(lang)]"
        }
        return "Profile \(user_id)"
    }

    /// Builds a greeting prompt.
    /// - Parameter name: Name to greet.
    /// - Parameter excited: Whether to add emphasis.
    @MCPPrompt
    func greetPrompt(name: String, excited: Bool = false) async -> [PromptMessage] {
        let punctuation = excited ? "!" : "."
        return [PromptMessage(role: .assistant, content: .init(text: "Hello \(name)\(punctuation)"))]
    }
}

@Suite("Generated Client Tests", .tags(.client))
struct MCPClientGenerationTests {
    @Test("Generated client is Sendable")
    func generatedClientIsSendable() {
        requireSendable(ClientTestServer.Client.self)
    }

    @Test("Preserves Int results and default parameters", .enabled(if: false))
    func preservesIntAndDefaults() async throws {
        let (server, client, proxy) = try await makeClient()
        defer { Task { await proxy.disconnect() } }

        #expect(try client.addInts(a: 1, b: 2) == 3)
        #expect(try client.multiply(a: 4) == 8)
        #expect(await server.lastMessage == nil)
    }

    @Test("Preserves Double results for async tools", .enabled(if: false))
    func preservesDoubleAsync() async throws {
        let (_, client, proxy) = try await makeClient()
        defer { Task { await proxy.disconnect() } }

        let result = try await client.addDoubles(a: 1.5, b: 2.25)
        #expect(result == 3.75)
    }

    @Test("Encodes enum inputs and arrays", .enabled(if: false))
    func encodesEnumInputs() async throws {
        let (_, client, proxy) = try await makeClient()
        defer { Task { await proxy.disconnect() } }

        #expect(try client.echoEnum(value: .beta) == "beta")
        #expect(try client.joinEnums(values: [.alpha, .beta]) == "alpha,beta")
        #expect(try client.describeEnum() == "none")
        #expect(try client.describeEnum(value: .alpha) == "alpha")
    }

    @Test("Decodes enum outputs", .enabled(if: false))
    func decodesEnumOutputs() async throws {
        let (_, client, proxy) = try await makeClient()
        defer { Task { await proxy.disconnect() } }

        let output = try client.makeEnum(flag: true)
        #expect(output == .one)
    }

    @Test("Round-trips schema types", .enabled(if: false))
    func roundTripsSchemaTypes() async throws {
        let (_, client, proxy) = try await makeClient()
        defer { Task { await proxy.disconnect() } }

        let payload = ClientPayload(count: 5, label: "ok")
        let result = try client.wrap(payload: payload)
        #expect(result.total == 5)
        #expect(result.status == "ok")
    }

    @Test("Handles void tool calls", .enabled(if: false))
    func handlesVoidToolCalls() async throws {
        let (server, client, proxy) = try await makeClient()
        defer { Task { await proxy.disconnect() } }

        try client.record(message: "hello")
        #expect(await server.lastMessage == "hello")
    }

    @Test("Generated client exposes standard resource APIs")
    func generatedClientUsesStandardResourceAPIs() async throws {
        let (_, client, proxy) = try await makeClient()
        defer { Task { await proxy.disconnect() } }

        let resources = try await client.listResources()
        #expect(resources.contains { $0.name == "summaryResource" })

        let profileContents = try await client.readResource(uri: URL(string: "users://7/profile")!)
        #expect(profileContents.first?.text == "Profile 7")

        let summaryContents = try await client.readResource(uri: URL(string: "app://summary")!)
        #expect(summaryContents.first?.text != nil)

        let templates = try await client.listResourceTemplates()
        #expect(templates.contains { $0.name == "userProfile" && $0.uriTemplate == "users://{user_id}/profile" })
        #expect(templates.contains { $0.name == "versionedUserProfile" && $0.uriTemplate == "users://{user_id}/profile/localized?lang={lang}" })
    }

    @Test("Generated client exposes standard prompt APIs")
    func generatedClientUsesStandardPromptAPIs() async throws {
        let (_, client, proxy) = try await makeClient()
        defer { Task { await proxy.disconnect() } }

        let prompts = try await client.listPrompts()
        #expect(prompts.contains { $0.name == "greetPrompt" })

        let result = try await client.getPrompt(name: "greetPrompt", arguments: ["name": "Taylor", "excited": true])
        #expect(result.description == "greetPrompt")
        #expect(result.messages.count == 1)
        #expect(result.messages.first?.content.text == "Hello Taylor!")
    }
}

private func makeClient() async throws -> (ClientTestServer, ClientTestServer.Client, MCPServerProxy) {
    let server = ClientTestServer()
    let config = MCPServerConfig.stdioHandles(server: server)
    let proxy = MCPServerProxy(config: config)
    try await proxy.connect()
    let client = ClientTestServer.Client(proxy: proxy)
    return (server, client, proxy)
}

extension Tag {
    @Tag static var client: Self
}

private func requireSendable<T: Sendable>(_: T.Type) {}
