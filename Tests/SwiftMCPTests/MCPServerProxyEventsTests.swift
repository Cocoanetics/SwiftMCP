#if Client && Server
import Foundation
import Testing
@testable import SwiftMCP

@MCPServer(name: "ProxyEventsTestServer", version: "1.0")
actor ProxyEventsTestServer {
    /// A continuous-integration run failed.
    ///
    /// - Parameter project: Only failures from this project.
    @MCPEvent(name: "ci.failed", delivery: ["webhook"])
    func ciFailed(project: String? = nil) -> String { "" }

    @MCPTool
    func noop() {}
}

@Suite("MCPServerProxy events client API")
struct MCPServerProxyEventsTests {
    private static let webhookURL = "https://example.com/mcp-events/hook"

    @Test("Modern era: listEvents returns ci.failed; subscribe and unsubscribe round-trip")
    func modernListSubscribeUnsubscribe() async throws {
        let server = ProxyEventsTestServer()
        let proxy = MCPServerProxy(config: .stdioHandles(server: server))
        await proxy.setEraPreference(.modern)
        proxy.meta["accessToken"] = .string("alice")
        try await proxy.connect()
        defer { Task { await proxy.disconnect() } }

        #expect(await proxy.negotiatedEra == .modern)

        let listed = try await proxy.listEvents()
        let event = try #require(listed.events.first { $0.name == "ci.failed" })
        #expect(event.delivery == ["webhook"])
        #expect(event.description == "A continuous-integration run failed.")

        let secret = WebhookSigner.generateSecret()
        let delivery = EventsWebhookDelivery(url: Self.webhookURL, secret: secret)
        let subscribed = try await proxy.subscribeEvent(
            name: "ci.failed",
            arguments: .object(["project": .string("SwiftMCP")]),
            delivery: delivery
        )
        #expect(!subscribed.id.isEmpty)
        #expect(subscribed.refreshBefore != nil)

        let stored = try await server.eventSubscriptionStore.subscriptions(principal: nil, now: Date())
        #expect(stored.count == 1)
        #expect(stored.first?.id == subscribed.id)

        try await proxy.unsubscribeEvent(
            name: "ci.failed",
            arguments: .object(["project": .string("SwiftMCP")]),
            delivery: EventsWebhookDelivery(url: Self.webhookURL)
        )
        #expect(try await server.eventSubscriptionStore.subscriptions(principal: nil, now: Date()).isEmpty)
    }

    @Test("Legacy era rejects listEvents, subscribeEvent and unsubscribeEvent")
    func legacyRejectsEventsAPI() async throws {
        let server = ProxyEventsTestServer()
        let proxy = MCPServerProxy(config: .stdioHandles(server: server))
        await proxy.setEraPreference(.legacy)
        proxy.meta["accessToken"] = .string("alice")
        try await proxy.connect()
        defer { Task { await proxy.disconnect() } }

        #expect(await proxy.negotiatedEra == .legacy)

        let delivery = EventsWebhookDelivery(url: Self.webhookURL, secret: WebhookSigner.generateSecret())

        await expectEventsUnsupported {
            _ = try await proxy.listEvents()
        }
        await expectEventsUnsupported {
            _ = try await proxy.subscribeEvent(name: "ci.failed", delivery: delivery)
        }
        await expectEventsUnsupported {
            try await proxy.unsubscribeEvent(
                name: "ci.failed",
                delivery: EventsWebhookDelivery(url: Self.webhookURL)
            )
        }
    }

    private func expectEventsUnsupported(_ body: () async throws -> Void) async {
        do {
            try await body()
            Issue.record("expected Events to be rejected on a non-supporting era")
        } catch let error as MCPServerProxyError {
            guard case .communicationError(let message) = error else {
                Issue.record("expected communicationError, got \(error)")
                return
            }
            #expect(message.contains("Events require"))
        } catch {
            Issue.record("expected MCPServerProxyError, got \(error)")
        }
    }
}
#endif
