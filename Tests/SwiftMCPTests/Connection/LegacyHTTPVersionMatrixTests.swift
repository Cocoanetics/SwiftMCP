#if Server
import Testing
import Foundation
import HTTPTypes
@testable import SwiftMCP

/// Streamable HTTP per legacy revision: each one negotiates, gates the session's
/// requests against it (with or without the `MCP-Protocol-Version` header),
/// rejects a header that disagrees, batches only where the revision allows it,
/// and keeps its request streams resumable — unlike the modern era.
@Suite("Legacy HTTP version matrix")
struct LegacyHTTPVersionMatrixTests {

    static let legacyVersions = ["2025-03-26", "2025-06-18", "2025-11-25"]

    private func jsonHeaders(version: String? = nil, sessionID: String? = nil) -> HTTPFields {
        var headers: HTTPFields = [.accept: "application/json, text/event-stream", .contentType: "application/json"]
        if let version {
            headers[.mcpProtocolVersion] = version
        }
        if let sessionID {
            headers[.mcpSessionID] = sessionID
        }
        return headers
    }

    /// The header a conforming client sends for `version`: none before `2025-06-18`.
    private func clientHeader(for version: String) -> String? {
        MCPProtocolVersion.profile(for: version)?.has(.protocolVersionHeader) == true ? version : nil
    }

    private func text(of body: InMemoryHTTPServerAdapter.ExchangeBody) async -> String {
        switch body {
        case .buffered(let data):
            return data.flatMap { String(bytes: $0, encoding: .utf8) } ?? ""
        case .sse(let stream):
            var data = Data()
            for await chunk in stream { data.append(chunk) }
            return String(bytes: data, encoding: .utf8) ?? ""
        }
    }

    /// Every JSON-RPC message in a response body, SSE-framed or plain JSON.
    private func messages(in text: String) -> [JSONRPCMessage] {
        let payloads: [String]
        if text.contains("data:") {
            payloads = text.split(separator: "\n")
                .filter { $0.hasPrefix("data:") }
                .map { String($0.dropFirst(5)).trimmingCharacters(in: .whitespaces) }
        } else {
            payloads = [text]
        }
        return payloads.flatMap { payload -> [JSONRPCMessage] in
            let data = Data(payload.utf8)
            if let batch = try? JSONDecoder().decode([JSONRPCMessage].self, from: data) {
                return batch
            }
            return (try? JSONDecoder().decode(JSONRPCMessage.self, from: data)).map { [$0] } ?? []
        }
    }

    private func initialize(_ adapter: InMemoryHTTPServerAdapter, version: String) async throws -> (String, String?) {
        let request = JSONRPCMessage.request(id: 1, method: "initialize", params: [
            "protocolVersion": .string(version),
            "capabilities": .object([:]),
            "clientInfo": .object(["name": .string("Matrix"), "version": .string("1.0")])
        ])
        let exchange = await adapter.send(
            method: .post, path: "/mcp",
            headerFields: jsonHeaders(version: clientHeader(for: version)),
            body: try HTTPTransportTestHelpers.encode(request)
        )
        let sessionID = try #require(exchange.headerFields[.mcpSessionID])
        let body = await text(of: exchange.body)
        guard case .response(let response)? = messages(in: body).first else {
            Issue.record("initialize did not answer: \(body)")
            return (sessionID, nil)
        }
        let initialized = JSONRPCMessage.notification(method: "notifications/initialized")
        _ = await adapter.send(
            method: .post, path: "/mcp",
            headerFields: jsonHeaders(version: clientHeader(for: version), sessionID: sessionID),
            body: try HTTPTransportTestHelpers.encode(initialized)
        )
        return (sessionID, response.result?["protocolVersion"]?.stringValue)
    }

    private func createContact(id: Int) -> JSONRPCMessage {
        .request(id: id, method: "tools/call", params: [
            "name": "createContact",
            "arguments": [
                "name": "Jane Roe", "email": "jane@example.com", "phone": "+1555",
                "age": 41, "isActive": true
            ]
        ])
    }

    @Test("Each legacy revision negotiates and gates the session's requests", arguments: legacyVersions)
    func negotiatesAndGates(version: String) async throws {
        let adapter = InMemoryHTTPServerAdapter(engine: HTTPSSETransport(server: ComplexTypesServer()))
        let (sessionID, negotiated) = try await initialize(adapter, version: version)
        #expect(negotiated == version)

        let structured = MCPProtocolVersion.profile(for: version)?.has(.structuredToolOutput) == true
        // With the header a conforming client sends, and without any header:
        // both resolve to the session's negotiated revision.
        for header in [clientHeader(for: version), nil] {
            let exchange = await adapter.send(
                method: .post, path: "/mcp",
                headerFields: jsonHeaders(version: header, sessionID: sessionID),
                body: try HTTPTransportTestHelpers.encode(createContact(id: 2))
            )
            #expect(exchange.status == .ok)
            guard case .response(let response)? = messages(in: await text(of: exchange.body)).first else {
                Issue.record("tools/call did not answer for \(version)")
                continue
            }
            #expect((response.result?["structuredContent"] != nil) == structured, "header: \(header ?? "none")")
        }
    }

    @Test("A header disagreeing with the session's revision is rejected")
    func mismatchedHeaderRejected() async throws {
        let adapter = InMemoryHTTPServerAdapter(engine: HTTPSSETransport(server: Calculator()))
        let (sessionID, _) = try await initialize(adapter, version: "2025-06-18")

        let exchange = await adapter.send(
            method: .post, path: "/mcp",
            headerFields: jsonHeaders(version: "2025-11-25", sessionID: sessionID),
            body: try HTTPTransportTestHelpers.encode(.request(id: 2, method: "tools/list", params: nil))
        )
        #expect(exchange.status == .badRequest)
        #expect(await text(of: exchange.body).contains("does not match"))
    }

    @Test("A revision the server does not serve is rejected on a session request", arguments: ["2024-11-05", "bogus"])
    func unservedHeaderRejected(header: String) async throws {
        let adapter = InMemoryHTTPServerAdapter(engine: HTTPSSETransport(server: Calculator()))
        let (sessionID, _) = try await initialize(adapter, version: "2025-11-25")

        let exchange = await adapter.send(
            method: .post, path: "/mcp",
            headerFields: jsonHeaders(version: header, sessionID: sessionID),
            body: try HTTPTransportTestHelpers.encode(.request(id: 2, method: "tools/list", params: nil))
        )
        #expect(exchange.status == .badRequest)
    }

    @Test("An unserved older proposal (2024-11-05) down-negotiates to the newest revision")
    func unknownProposalDownNegotiates() async throws {
        let adapter = InMemoryHTTPServerAdapter(engine: HTTPSSETransport(server: Calculator()))
        let (_, negotiated) = try await initialize(adapter, version: "2024-11-05")
        #expect(negotiated == MCPProtocolVersion.latest)
    }

    @Test("JSON-RPC batches are answered only on revisions that define them", arguments: legacyVersions)
    func batchingByRevision(version: String) async throws {
        let adapter = InMemoryHTTPServerAdapter(engine: HTTPSSETransport(server: Calculator()))
        let (sessionID, _) = try await initialize(adapter, version: version)

        let batch = [
            JSONRPCMessage.request(id: 2, method: "tools/list", params: nil),
            JSONRPCMessage.request(id: 3, method: "ping", params: nil)
        ]
        let exchange = await adapter.send(
            method: .post, path: "/mcp",
            headerFields: jsonHeaders(version: clientHeader(for: version), sessionID: sessionID),
            body: try JSONEncoder().encode(batch)
        )
        let replies = messages(in: await text(of: exchange.body))

        if MCPProtocolVersion.profile(for: version)?.has(.jsonRPCBatching) == true {
            #expect(exchange.status == .ok)
            let ids = Set(replies.compactMap { message -> JSONRPCID? in
                if case .response(let response) = message { return response.id }
                return nil
            })
            #expect(ids == [.integer(2), .integer(3)])
        } else {
            #expect(exchange.status == .badRequest)
            guard case .errorResponse(let error)? = replies.first else {
                Issue.record("expected a -32600 error for \(version)")
                return
            }
            #expect(error.error.code == -32600)
        }
    }

    @Test("Legacy request streams carry resumable event ids; modern ones do not")
    func resumabilityByEra() async throws {
        let adapter = InMemoryHTTPServerAdapter(engine: HTTPSSETransport(server: Calculator()))
        let (sessionID, _) = try await initialize(adapter, version: "2025-11-25")

        let legacy = await adapter.send(
            method: .post, path: "/mcp",
            headerFields: jsonHeaders(version: "2025-11-25", sessionID: sessionID),
            body: try HTTPTransportTestHelpers.encode(.request(id: 2, method: "tools/list", params: nil))
        )
        let legacyText = await text(of: legacy.body)
        #expect(legacyText.split(separator: "\n").contains { $0.hasPrefix("id:") })

        let modernRequest = JSONRPCMessage.request(id: 3, method: "tools/list", params: .object([
            "_meta": .object([MCPMetaKey.protocolVersion: .string(MCPProtocolVersion.modern)])
        ]))
        var modernHeaders = jsonHeaders(version: MCPProtocolVersion.modern)
        modernHeaders[.mcpMethod] = "tools/list"
        let modern = await adapter.send(
            method: .post, path: "/mcp", headerFields: modernHeaders,
            body: try HTTPTransportTestHelpers.encode(modernRequest)
        )
        #expect(modern.status == .ok)
        let modernText = await text(of: modern.body)
        #expect(!messages(in: modernText).isEmpty)
        #expect(!modernText.split(separator: "\n").contains { $0.hasPrefix("id:") })
    }
}
#endif
