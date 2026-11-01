#if Server
import Testing
import Foundation
import HTTPTypes
@testable import SwiftMCP

/// Modern `subscriptions/listen`: acknowledgement first, tagged opt-in notifications,
/// clean teardown on disconnect, and the legacy GET / `resources/subscribe` retired.
@Suite("Modern subscriptions/listen", .serialized)
struct ModernSubscriptionsListenTests {

    private let listenID = 7

    private func headers(method: String) -> HTTPFields {
        [
            .accept: "application/json, text/event-stream", .contentType: "application/json",
            .mcpProtocolVersion: "2026-07-28", .mcpMethod: method
        ]
    }

    private func listenBody(_ notifications: JSONValue) throws -> Data {
        try HTTPTransportTestHelpers.encode(JSONRPCMessage.request(
            id: listenID, method: "subscriptions/listen",
            params: .object([
                "_meta": .object(["io.modelcontextprotocol/protocolVersion": .string("2026-07-28")]),
                "notifications": notifications
            ])
        ))
    }

    /// Reads the open stream until `count` SSE events arrived, returning their JSON payloads.
    private func events(
        _ iterator: inout AsyncStream<Data>.AsyncIterator, count: Int
    ) async -> [[String: JSONValue]] {
        var buffer = ""
        var result: [[String: JSONValue]] = []
        while result.count < count, let chunk = await iterator.next() {
            buffer += String(bytes: chunk, encoding: .utf8) ?? ""
            while let range = buffer.range(of: "\n\n") {
                let block = String(buffer[..<range.lowerBound])
                buffer.removeSubrange(..<range.upperBound)
                for line in block.split(separator: "\n") where line.hasPrefix("data:") {
                    let json = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                    if let value = try? JSONDecoder().decode(JSONValue.self, from: Data(json.utf8)),
                       let object = value.dictionaryValue {
                        result.append(object)
                    }
                }
            }
        }
        return result
    }

    private func subscriptionID(of event: [String: JSONValue]) -> JSONValue? {
        event["params"]?["_meta"]?["io.modelcontextprotocol/subscriptionId"]
    }

    @Test("Acknowledges first, then delivers only opted-in notifications, tagged")
    func acknowledgesThenTags() async throws {
        let transport = HTTPSSETransport(server: Calculator())
        let adapter = InMemoryHTTPServerAdapter(engine: transport)
        let exchange = await adapter.send(
            method: .post, path: "/mcp", headerFields: headers(method: "subscriptions/listen"),
            body: try listenBody(.object(["toolsListChanged": .bool(true)]))
        )
        #expect(exchange.status == .ok)
        #expect(exchange.headerFields[.mcpSessionID] == nil)
        guard case .sse(let stream) = exchange.body else {
            Issue.record("expected an SSE body")
            return
        }
        var iterator = stream.makeAsyncIterator()

        await transport.broadcastPromptsListChanged()   // not requested
        await transport.broadcastToolsListChanged()

        let received = await events(&iterator, count: 2)
        #expect(received.count == 2)
        #expect(received[0]["method"]?.stringValue == "notifications/subscriptions/acknowledged")
        #expect(received[0]["params"]?["notifications"]?["toolsListChanged"]?.boolValue == true)
        #expect(subscriptionID(of: received[0]) == .integer(listenID))
        #expect(received[1]["method"]?.stringValue == "notifications/tools/list_changed")
        #expect(subscriptionID(of: received[1]) == .integer(listenID))
    }

    @Test("resourceSubscriptions only delivers updates for the listed URIs")
    func resourceUpdatedFiltered() async throws {
        let transport = HTTPSSETransport(server: PushFixtureServer())
        let adapter = InMemoryHTTPServerAdapter(engine: transport)
        let exchange = await adapter.send(
            method: .post, path: "/mcp", headerFields: headers(method: "subscriptions/listen"),
            body: try listenBody(.object(["resourceSubscriptions": .array([.string("push://status")])]))
        )
        guard case .sse(let stream) = exchange.body else {
            Issue.record("expected an SSE body")
            return
        }
        var iterator = stream.makeAsyncIterator()

        await transport.broadcastResourceUpdated(uri: URL(string: "push://other")!)
        await transport.broadcastResourceUpdated(uri: URL(string: "push://status")!)

        let received = await events(&iterator, count: 2)
        #expect(received.count == 2)
        #expect(received[1]["method"]?.stringValue == "notifications/resources/updated")
        #expect(received[1]["params"]?["uri"]?.stringValue == "push://status")
        #expect(subscriptionID(of: received[1]) == .integer(listenID))
    }

    @Test("The acknowledgement omits notification types the server cannot produce")
    func acknowledgementNarrowedToCapabilities() async throws {
        let transport = HTTPSSETransport(server: Calculator())
        let adapter = InMemoryHTTPServerAdapter(engine: transport)
        let exchange = await adapter.send(
            method: .post, path: "/mcp", headerFields: headers(method: "subscriptions/listen"),
            body: try listenBody(.object([
                "toolsListChanged": .bool(true), "promptsListChanged": .bool(true)
            ]))
        )
        guard case .sse(let stream) = exchange.body else {
            Issue.record("expected an SSE body")
            return
        }
        var iterator = stream.makeAsyncIterator()
        let ack = await events(&iterator, count: 1)
        let honored = ack.first?["params"]?["notifications"]
        #expect(honored?["toolsListChanged"]?.boolValue == true)
        #expect(honored?["promptsListChanged"] == nil)
    }

    @Test("The stream ends cleanly when the client disconnects")
    func disconnectEndsStream() async throws {
        let transport = HTTPSSETransport(server: Calculator())
        let adapter = InMemoryHTTPServerAdapter(engine: transport)
        let exchange = await adapter.send(
            method: .post, path: "/mcp", headerFields: headers(method: "subscriptions/listen"),
            body: try listenBody(.object(["toolsListChanged": .bool(true)]))
        )
        guard case .sse(let stream) = exchange.body else {
            Issue.record("expected an SSE body")
            return
        }
        var iterator = stream.makeAsyncIterator()
        _ = await events(&iterator, count: 1)

        exchange.connection?.terminate()
        // The stream finishes and the subscription (with its ephemeral session) is gone.
        while await iterator.next() != nil {}
        #expect(await transport.sessionManager.listenSubscriptions.isEmpty)
        #expect(await transport.sessionManager.sessionIDs.isEmpty)
    }

    @Test("A malformed filter is rejected with -32602 before any stream opens")
    func malformedFilterRejected() async throws {
        let transport = HTTPSSETransport(server: Calculator())
        let adapter = InMemoryHTTPServerAdapter(engine: transport)
        let exchange = await adapter.send(
            method: .post, path: "/mcp", headerFields: headers(method: "subscriptions/listen"),
            body: try listenBody(.object(["toolsListChanged": .string("yes")]))
        )
        #expect(exchange.status == .badRequest)
        #expect(await transport.sessionManager.listenSubscriptions.isEmpty)
    }

    @Test("Modern requests cannot use the GET stream or resources/subscribe")
    func legacyMechanismsRetiredForModern() async throws {
        let transport = HTTPSSETransport(server: PushFixtureServer())
        let adapter = InMemoryHTTPServerAdapter(engine: transport)

        var getHeaders = headers(method: "subscriptions/listen")
        getHeaders[.accept] = "text/event-stream"
        let get = await adapter.send(method: .get, path: "/mcp", headerFields: getHeaders)
        #expect(get.status == .methodNotAllowed)

        let subscribe = await adapter.send(
            method: .post, path: "/mcp", headerFields: headers(method: "resources/subscribe"),
            body: try HTTPTransportTestHelpers.encode(JSONRPCMessage.request(
                id: 1, method: "resources/subscribe",
                params: .object([
                    "_meta": .object(["io.modelcontextprotocol/protocolVersion": .string("2026-07-28")]),
                    "uri": .string("push://status")
                ])
            ))
        )
        #expect(subscribe.status == .notFound)
    }

    @Test("Legacy sessions keep resources/subscribe and cannot call subscriptions/listen")
    func legacyUnchanged() async throws {
        let transport = HTTPSSETransport(server: PushFixtureServer())
        let adapter = InMemoryHTTPServerAdapter(engine: transport)
        let base: HTTPFields = [.accept: "application/json, text/event-stream", .contentType: "application/json"]

        let initialize = await adapter.send(
            method: .post, path: "/mcp", headerFields: base,
            body: try HTTPTransportTestHelpers.encode(HTTPTransportTestHelpers.initializeRequest())
        )
        let sessionID = try #require(initialize.headerFields[.mcpSessionID])
        if case .sse(let stream) = initialize.body { for await _ in stream {} }

        var sessionHeaders = base
        sessionHeaders[.mcpSessionID] = sessionID
        let note = await adapter.send(
            method: .post, path: "/mcp", headerFields: sessionHeaders,
            body: try HTTPTransportTestHelpers.encode(JSONRPCMessage.notification(method: "notifications/initialized"))
        )
        #expect(note.status == .accepted)

        for (method, params, expectError) in [
            ("resources/subscribe", JSONValue.object(["uri": .string("push://status")]), false),
            ("subscriptions/listen", JSONValue.object(["notifications": .object([:])]), true)
        ] {
            let reply = await adapter.send(
                method: .post, path: "/mcp", headerFields: sessionHeaders,
                body: try HTTPTransportTestHelpers.encode(JSONRPCMessage.request(id: 5, method: method, params: params))
            )
            guard case .sse(let stream) = reply.body else {
                Issue.record("expected an SSE reply for \(method)")
                continue
            }
            var text = ""
            for await chunk in stream { text += String(bytes: chunk, encoding: .utf8) ?? "" }
            #expect(text.contains("\"error\"") == expectError, "\(method): \(text)")
        }
    }
}
#endif
