#if Server && Client
import Testing
import Foundation
@testable import SwiftMCP

/// A contact, returned as structured tool output.
@Schema
struct MatrixContact: Sendable, Codable, Equatable {
    let name: String
    let age: Int
}

/// Exercises every version-dependent surface a client sees.
@MCPServer(name: "VersionMatrix", title: "Version Matrix")
actor VersionMatrixServer {
    private(set) var savedSession: Session?

    /// A subscribable resource.
    @MCPResource("matrix://status")
    func status() -> String {
        "ok"
    }

    /// A greeting prompt.
    @MCPPrompt
    func greeting() -> String {
        "Hello"
    }

    /// Makes a contact.
    /// - Parameters:
    ///   - name: The contact's name.
    ///   - age: The contact's age.
    /// - Returns: The contact.
    @MCPTool
    func makeContact(name: String, age: Int) -> MatrixContact {
        MatrixContact(name: name, age: age)
    }

    /// Links to the status resource.
    @MCPTool
    func statusLink() -> MCPResourceLink {
        MCPResourceLink(uri: URL(string: "matrix://status")!, name: "Status")
    }

    /// Captures the calling session, for pushes outside a request.
    @MCPTool
    func saveSession() -> String {
        savedSession = Session.current
        return "saved"
    }
}

/// Records resource-updated pushes.
private final class UpdateRecorder: MCPServerProxyResourceNotificationHandling, @unchecked Sendable {
    let events: AsyncStream<String>
    private let continuation: AsyncStream<String>.Continuation

    init() {
        (events, continuation) = AsyncStream.makeStream()
    }

    func mcpServerProxy(_ proxy: MCPServerProxy, resourceUpdatedAt uri: URL) async {
        continuation.yield(uri.absoluteString)
    }

    /// The first push, or `nil` after `seconds`.
    func next(within seconds: Double) async -> String? {
        await withTaskGroup(of: String?.self) { group in
            group.addTask {
                for await event in self.events { return event }
                return nil
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return nil
            }
            defer { group.cancelAll() }
            return await group.next() ?? nil
        }
    }
}

/// A real client against a real server, once per protocol revision and transport:
/// the client proposes the revision (`preferredProtocolVersion`) and every
/// version-gated surface must come out as that revision defines it.
@Suite("Protocol version end-to-end matrix", .loopbackShared)
struct ProtocolVersionEndToEndTests {

    enum TransportKind: String, Sendable, CaseIterable {
        case inProcess = "in-process stdio"
        case http = "streamable HTTP"
    }

    struct MatrixCase: Sendable, CustomTestStringConvertible {
        let version: String
        let transport: TransportKind
        var testDescription: String { "\(version) over \(transport.rawValue)" }
    }

    static let versions = ["2025-03-26", "2025-06-18", "2025-11-25", MCPProtocolVersion.modern]

    static let cases: [MatrixCase] = versions.flatMap { version in
        TransportKind.allCases.map { MatrixCase(version: version, transport: $0) }
    }

    /// A connected proxy plus how to push `resources/updated` to it and tear down.
    private struct Connection {
        let proxy: MCPServerProxy
        let push: @Sendable (URL) async throws -> Void
        let stop: @Sendable () async -> Void
    }

    private func connect(
        _ server: VersionMatrixServer,
        over kind: TransportKind,
        version: String,
        recorder: UpdateRecorder
    ) async throws -> Connection {
        switch kind {
        case .inProcess:
            let proxy = MCPServerProxy(config: .stdioHandles(server: server))
            try await prepareAndConnect(proxy, version: version, recorder: recorder)
            return Connection(
                proxy: proxy,
                push: { uri in
                    let session = try #require(await server.savedSession)
                    try await session.work { try await $0.sendResourceUpdated(uri: uri) }
                },
                stop: { await proxy.disconnect() }
            )
        case .http:
            let transport = HTTPSSETransport(server: server, host: "127.0.0.1", port: 0)
            try await transport.start()
            let url = try #require(URL(string: "http://127.0.0.1:\(transport.port)/mcp"))
            let proxy = MCPServerProxy(config: .sse(config: MCPServerSseConfig(url: url)))
            try await prepareAndConnect(proxy, version: version, recorder: recorder)
            return Connection(
                proxy: proxy,
                push: { uri in await transport.broadcastResourceUpdated(uri: uri) },
                stop: {
                    await proxy.disconnect()
                    try? await transport.stop()
                }
            )
        }
    }

    private func prepareAndConnect(_ proxy: MCPServerProxy, version: String, recorder: UpdateRecorder) async throws {
        await proxy.setPreferredProtocolVersion(version)
        await proxy.setResourceNotificationHandler(recorder)
        try await proxy.connect()
    }

    @Test("A client proposing the revision gets that revision's surface", .timeLimit(.minutes(1)), arguments: cases)
    func revisionSurface(_ testCase: MatrixCase) async throws {
        let profile = try #require(MCPProtocolVersion.profile(for: testCase.version))
        let server = VersionMatrixServer()
        let recorder = UpdateRecorder()
        let connection = try await connect(
            server, over: testCase.transport, version: testCase.version, recorder: recorder
        )
        let proxy = connection.proxy

        // Negotiation.
        if profile.isModern {
            #expect(await proxy.negotiatedEra == .modern)
            #expect(await proxy.modernProtocolVersion == testCase.version)
            if testCase.transport == .http {
                // No `Mcp-Session-Id` (line transports keep a local connection id).
                #expect(await proxy.sessionID == nil)
            }
        } else {
            #expect(await proxy.negotiatedEra == .legacy)
            #expect(await proxy.negotiatedProtocolVersion == testCase.version)
            if testCase.transport == .http {
                #expect(await proxy.sessionID != nil)
            }
        }
        #expect(await proxy.serverName == "VersionMatrix")
        #expect((await proxy.serverTitle == "Version Matrix") == profile.has(.titleField))

        // Ping is a liveness check in every revision.
        try await proxy.ping()

        // Structured output: schema and value only where the revision defines them,
        // and the typed call decodes either way.
        let tools = try await proxy.listTools()
        let makeContact = try #require(tools.first { $0.name == "makeContact" })
        #expect((makeContact.outputSchema != nil) == profile.has(.structuredToolOutput))
        let arguments: JSONDictionary = ["name": "Ada", "age": 36]
        let raw = try await proxy.callToolResult("makeContact", arguments: arguments)
        #expect((raw.structuredContent != nil) == profile.has(.structuredToolOutput))
        let contact = try await proxy.callTool("makeContact", arguments: arguments, as: MatrixContact.self)
        #expect(contact == MatrixContact(name: "Ada", age: 36))

        // Resource links, degraded to text before they existed.
        let link = try await proxy.callToolResult("statusLink")
        let linkType = link.content.first?["type"]?.stringValue
        #expect(linkType == (profile.has(.resourceLinks) ? "resource_link" : "text"))

        // Resources and prompts.
        let contents = try await proxy.readResource(uri: try #require(URL(string: "matrix://status")))
        #expect(!contents.isEmpty)
        #expect(try await proxy.listPrompts().contains { $0.name == "greeting" })

        // Pushes: `resources/subscribe` (legacy) or `subscriptions/listen` (modern).
        let uri = try #require(URL(string: "matrix://status"))
        try await proxy.subscribeResource(uri: uri)
        _ = try await proxy.callTool("saveSession")
        try await connection.push(uri)
        #expect(await recorder.next(within: 10) == uri.absoluteString)

        await connection.stop()
    }
}
#endif
