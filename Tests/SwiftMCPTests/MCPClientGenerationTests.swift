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
}

@Suite("Generated Client Tests", .tags(.client))
struct MCPClientGenerationTests {
    @Test("Preserves Int results and default parameters")
    func preservesIntAndDefaults() async throws {
        let (server, client, proxy) = try await makeClient()
        defer { Task { await proxy.disconnect() } }

        #expect(try client.addInts(a: 1, b: 2) == 3)
        #expect(try client.multiply(a: 4) == 8)
        #expect(await server.lastMessage == nil)
    }

    @Test("Preserves Double results for async tools")
    func preservesDoubleAsync() async throws {
        let (_, client, proxy) = try await makeClient()
        defer { Task { await proxy.disconnect() } }

        let result = try await client.addDoubles(a: 1.5, b: 2.25)
        #expect(result == 3.75)
    }

    @Test("Encodes enum inputs and arrays")
    func encodesEnumInputs() async throws {
        let (_, client, proxy) = try await makeClient()
        defer { Task { await proxy.disconnect() } }

        #expect(try client.echoEnum(value: .beta) == "beta")
        #expect(try client.joinEnums(values: [.alpha, .beta]) == "alpha,beta")
        #expect(try client.describeEnum() == "none")
        #expect(try client.describeEnum(value: .alpha) == "alpha")
    }

    @Test("Decodes enum outputs")
    func decodesEnumOutputs() async throws {
        let (_, client, proxy) = try await makeClient()
        defer { Task { await proxy.disconnect() } }

        let output = try client.makeEnum(flag: true)
        #expect(output == .one)
    }

    @Test("Round-trips schema types")
    func roundTripsSchemaTypes() async throws {
        let (_, client, proxy) = try await makeClient()
        defer { Task { await proxy.disconnect() } }

        let payload = ClientPayload(count: 5, label: "ok")
        let result = try client.wrap(payload: payload)
        #expect(result.total == 5)
        #expect(result.status == "ok")
    }

    @Test("Handles void tool calls")
    func handlesVoidToolCalls() async throws {
        let (server, client, proxy) = try await makeClient()
        defer { Task { await proxy.disconnect() } }

        try client.record(message: "hello")
        #expect(await server.lastMessage == "hello")
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
