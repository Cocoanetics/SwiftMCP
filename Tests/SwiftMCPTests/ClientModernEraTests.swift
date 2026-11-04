#if Client
import Testing
import Foundation
@testable import SwiftMCP

@Suite("Modern client era negotiation & request path")
struct ClientModernEraTests {
    @Test("Modern mode selects the era from discover and never sends initialize")
    func modernSkipsInitialize() async throws {
        let fake = makeModernServer()
        let proxy = await makeModernProxy(fake, preference: .modern)
        try await proxy.establishConnection(clientName: "tester", clientVersion: "9")

        #expect(await proxy.negotiatedEra == .modern)
        #expect(await proxy.modernProtocolVersion == MCPProtocolVersion.modern)
        #expect(await proxy.lastDiscover?.supportedVersions.first == MCPProtocolVersion.modern)
        #expect(await proxy.serverName == "Fake")

        let text = try await proxy.callTool("anything")
        #expect(text == "hi")

        let call = try #require(fake.requests("tools/call").first)
        let meta = try #require(call.params?["_meta"]?.dictionaryValue)
        #expect(meta[MCPMetaKey.protocolVersion]?.stringValue == MCPProtocolVersion.modern)
        #expect(meta[MCPMetaKey.clientInfo]?["name"]?.stringValue == "tester")
        #expect(meta[MCPMetaKey.clientInfo]?["version"]?.stringValue == "9")
        #expect(meta[MCPMetaKey.logLevel] == nil)
        #expect(fake.requests("initialize").isEmpty)
        let notifications = fake.received.filter { $0.method == "notifications/initialized" }
        #expect(notifications.isEmpty)
        await proxy.disconnect()
    }

    @Test("Per-request log level is sent only when configured")
    func logLevelOptIn() async throws {
        let fake = makeModernServer()
        let proxy = await makeModernProxy(fake, preference: .modern)
        try await proxy.establishConnection(clientName: "t", clientVersion: "1")
        await proxy.setRequestLogLevel(.warning)
        _ = try await proxy.callTool("x")
        let call = try #require(fake.requests("tools/call").first)
        #expect(call.params?["_meta"]?[MCPMetaKey.logLevel]?.stringValue == "warning")
        await proxy.disconnect()
    }

    @Test("Auto falls back to initialize when the probe answers -32601")
    func autoFallsBackOnMethodNotFound() async throws {
        let fake = FakeLineServer { message in
            guard case .request(let request) = message else { return nil }
            return request.method == "initialize"
                ? FakeLineServer.ok(request, FakeLineServer.initializeResult)
                : FakeLineServer.fail(request, -32601)
        }
        let proxy = await makeModernProxy(fake, preference: .auto)
        try await proxy.establishConnection(clientName: "t", clientVersion: "1")
        #expect(await proxy.negotiatedEra == .legacy)
        #expect(await proxy.negotiatedProtocolVersion == MCPProtocolVersion.latest)
        #expect(fake.requests("server/discover").count == 1)
        #expect(fake.requests("initialize").count == 1)
        await proxy.disconnect()
    }

    @Test("Auto falls back when discover lists only legacy versions")
    func autoFallsBackOnLegacyOnlyList() async throws {
        let fake = FakeLineServer { message in
            guard case .request(let request) = message else { return nil }
            return request.method == "initialize"
                ? FakeLineServer.ok(request, FakeLineServer.initializeResult)
                : FakeLineServer.ok(request, FakeLineServer.discoverResult(["2025-11-25"]))
        }
        let proxy = await makeModernProxy(fake, preference: .auto)
        try await proxy.establishConnection(clientName: "t", clientVersion: "1")
        #expect(await proxy.negotiatedEra == .legacy)
        await proxy.disconnect()
    }

    @Test("Auto falls back when the probe times out")
    func autoFallsBackOnTimeout() async throws {
        let fake = FakeLineServer { message in
            guard case .request(let request) = message, request.method == "initialize" else { return nil }
            return FakeLineServer.ok(request, FakeLineServer.initializeResult)
        }
        let proxy = await makeModernProxy(fake, preference: .auto)
        await proxy.setEraProbeTimeout(0.2)
        try await proxy.establishConnection(clientName: "t", clientVersion: "1")
        #expect(await proxy.negotiatedEra == .legacy)
        await proxy.disconnect()
    }

    @Test("Modern mode against a legacy server fails with the typed error")
    func modernAgainstLegacyFails() async throws {
        let fake = FakeLineServer { message in
            guard case .request(let request) = message else { return nil }
            return FakeLineServer.fail(request, -32601)
        }
        let proxy = await makeModernProxy(fake, preference: .modern)
        do {
            try await proxy.establishConnection(clientName: "t", clientVersion: "1")
            Issue.record("expected unsupportedProtocolVersion")
        } catch MCPServerProxyError.unsupportedProtocolVersion {
            // expected
        }
        #expect(fake.requests("initialize").isEmpty)
        await proxy.disconnect()
    }

    @Test("Modern mode reports the server's list when no modern revision overlaps")
    func modernNoOverlap() async throws {
        let fake = makeModernServer(versions: ["2099-01-01", "2025-11-25"])
        let proxy = await makeModernProxy(fake, preference: .modern)
        do {
            try await proxy.establishConnection(clientName: "t", clientVersion: "1")
            Issue.record("expected unsupportedProtocolVersion")
        } catch MCPServerProxyError.unsupportedProtocolVersion(let supported) {
            #expect(supported == ["2099-01-01", "2025-11-25"])
        }
        await proxy.disconnect()
    }

    @Test("ping on a modern connection to a dual-era server is a legacy ping")
    func modernPingIsLegacyShaped() async throws {
        let fake = FakeLineServer { message in
            guard case .request(let request) = message else { return nil }
            switch request.method {
            case "server/discover":
                let versions = [MCPProtocolVersion.modern, "2025-11-25"]
                return FakeLineServer.ok(request, FakeLineServer.discoverResult(versions))
            case "ping":
                let isLegacy = request.params?["_meta"] == nil
                return isLegacy ? FakeLineServer.ok(request, [:]) : FakeLineServer.fail(request, -32601)
            default:
                return FakeLineServer.fail(request, -32601)
            }
        }
        let proxy = await makeModernProxy(fake, preference: .auto)
        try await proxy.establishConnection(clientName: "t", clientVersion: "1")
        #expect(await proxy.negotiatedEra == .modern)

        try await proxy.ping()
        let ping = try #require(fake.requests("ping").first)
        #expect(ping.params?["_meta"] == nil)
        #expect(fake.requests("server/discover").count == 1)
        await proxy.disconnect()
    }

    @Test("ping on a modern-only server probes server/discover instead")
    func modernOnlyPingUsesDiscover() async throws {
        let fake = makeModernServer(versions: [MCPProtocolVersion.modern])
        let proxy = await makeModernProxy(fake, preference: .auto)
        try await proxy.establishConnection(clientName: "t", clientVersion: "1")
        #expect(await proxy.negotiatedEra == .modern)

        try await proxy.ping()
        #expect(fake.requests("ping").isEmpty)
        #expect(fake.requests("server/discover").count == 2)
        await proxy.disconnect()
    }

    @Test("The default preference is auto")
    func defaultIsAuto() async throws {
        let fresh = MCPServerProxy(config: .stdioHandles(server: ClientDiscoverTestServer()))
        #expect(await fresh.eraPreference == .auto)
    }

    @Test("The legacy preference sends no discover probe")
    func legacySkipsProbe() async throws {
        let fake = FakeLineServer { message in
            guard case .request(let request) = message else { return nil }
            return FakeLineServer.ok(request, FakeLineServer.initializeResult)
        }
        let proxy = await makeModernProxy(fake, preference: .legacy)
        try await proxy.establishConnection(clientName: "t", clientVersion: "1")
        #expect(fake.requests("server/discover").isEmpty)
        #expect(await proxy.negotiatedEra == .legacy)
        await proxy.disconnect()
    }

    // MARK: - Mcp-Param headers

    @Test("Mcp-Param values: ASCII verbatim, non-ASCII sentinel, JSON for non-strings")
    func paramEncoding() {
        #expect(MCPParamHeader.encode(.string("us-west")) == "us-west")
        #expect(MCPParamHeader.encode(.string("Zürich")) == "=?base64?\(Data("Zürich".utf8).base64EncodedString())?=")
        let padded = Data(" padded ".utf8).base64EncodedString()
        #expect(MCPParamHeader.encode(.string(" padded ")) == "=?base64?\(padded)?=")
        #expect(MCPParamHeader.encode(.string("a\nb"))?.hasPrefix("=?base64?") == true)
        #expect(MCPParamHeader.encode(.integer(42)) == "42")
        #expect(MCPParamHeader.encode(.bool(true)) == "true")
        #expect(MCPParamHeader.encode(.object(["b": .integer(1), "a": .integer(2)])) == "{\"a\":2,\"b\":1}")
        #expect(MCPParamHeader.encode(.null) == nil)
    }

    @Test("Modern HTTP headers carry method, name and mirrored parameters")
    func modernHeaders() async throws {
        let fake = makeModernServer()
        let proxy = await makeModernProxy(fake, preference: .modern)
        await proxy.recordHeaderParameters(from: [
            "tools": .array([.object([
                "name": .string("deploy"),
                "inputSchema": .object(["properties": .object([
                    "region": .object(["x-mcp-header": .bool(true)]),
                    "count": .object(["x-mcp-header": .string("N")]),
                    "note": .object([:])
                ])])
            ])])
        ])
        let call = JSONRPCMessage.request(id: 1, method: "tools/call", params: .object([
            "name": .string("deploy"),
            "arguments": .object(["region": .string("Zürich"), "count": .integer(3), "note": .string("x")])
        ]))
        let headers = try await proxy.modernRequestHeaders(for: call)
        #expect(headers["Mcp-Method"] == "tools/call")
        #expect(headers["Mcp-Name"] == "deploy")
        #expect(headers["Mcp-Param-region"] == "=?base64?\(Data("Zürich".utf8).base64EncodedString())?=")
        #expect(headers["Mcp-Param-N"] == "3")
        #expect(headers["Mcp-Param-note"] == nil)

        let read = JSONRPCMessage.request(
            id: 2, method: "resources/read", params: .object(["uri": .string("file:///a")])
        )
        let readHeaders = try await proxy.modernRequestHeaders(for: read)
        #expect(readHeaders["Mcp-Name"] == "file:///a")
        await proxy.disconnect()
    }

    @Test("A modern tools/call keeps the typed -32001 error")
    func toolCallTypedError() async throws {
        let fake = makeModernServer { FakeLineServer.fail($0, -32001) }
        let proxy = await makeModernProxy(fake, preference: .modern)
        try await proxy.establishConnection(clientName: "t", clientVersion: "1")
        do {
            _ = try await proxy.callTool("x")
            Issue.record("expected headerMismatch")
        } catch MCPServerProxyError.headerMismatch {
            // expected
        }
        await proxy.disconnect()
    }

    @Test("invalidateToolsCache drops the mirrored-header metadata")
    func invalidateClearsHeaderParameters() async throws {
        let proxy = await makeModernProxy(makeModernServer(), preference: .modern)
        await proxy.recordHeaderParameters(from: ["tools": .array([])])
        #expect(await proxy.headerParameters != nil)
        await proxy.invalidateToolsCache()
        #expect(await proxy.headerParameters == nil)
        await proxy.disconnect()
    }

    @Test("Modern mode rejects the classic SSE transport without sending initialize")
    func modernRejectsClassicSSE() async throws {
        let url = try #require(URL(string: "http://127.0.0.1:9/sse"))
        let proxy = MCPServerProxy(config: .sse(config: MCPServerSseConfig(url: url)))
        await proxy.setEraPreference(.modern)
        do {
            try await proxy.connect()
            Issue.record("expected unsupportedProtocolVersion")
        } catch MCPServerProxyError.unsupportedProtocolVersion {
            // expected
        }
    }

    @Test("Modern connections send the selected version header and no session id")
    func modernVersionHeader() async throws {
        let fake = makeModernServer()
        let proxy = await makeModernProxy(fake, preference: .modern)
        try await proxy.establishConnection(clientName: "t", clientVersion: "1")
        #expect(await proxy.mcpProtocolVersionHeaderValue == MCPProtocolVersion.modern)
        await proxy.disconnect()
    }
}

extension MCPServerProxy {
    func setEraPreference(_ value: MCPClientEraPreference) { eraPreference = value }
    func setEraProbeTimeout(_ value: TimeInterval) { eraProbeTimeout = value }
    func setRequestLogLevel(_ value: LogLevel?) { requestLogLevel = value }
    func setInputHandler(_ value: (any MCPClientInputHandler)?) { inputHandler = value }
    func setMaxInputRounds(_ value: Int) { maxInputRounds = value }
}
#endif
