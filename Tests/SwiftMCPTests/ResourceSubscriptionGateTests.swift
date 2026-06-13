import Foundation
import Testing
@testable import SwiftMCP

/// Verifies that `resources/subscribe` and `resources/unsubscribe` are only
/// honored by servers that actually advertise the `resources` capability.
///
/// The `@MCPServer` macro always adds `MCPResourceProviding` conformance, so the
/// gate keys off a non-empty `mcpResourceMetadata` — the same condition used when
/// advertising capabilities during `initialize`.
@Suite("Resource Subscription Gate", .tags(.unit))
struct ResourceSubscriptionGateTests {
    private static let unsupportedMessage = "Server does not support resource subscriptions"

    private func subscribeRequest(method: String, id: Int = 1) -> JSONRPCMessage {
        .request(
            id: id,
            method: method,
            params: ["uri": "config://app"]
        )
    }

    @Test("Server without resources rejects resources/subscribe")
    func nonResourceServerRejectsSubscribe() async throws {
        let calculator = Calculator()

        guard let message = await calculator.handleMessage(subscribeRequest(method: "resources/subscribe")) else {
            Issue.record("Expected a response message")
            return
        }
        guard case .errorResponse(let response) = message else {
            Issue.record("Expected errorResponse case")
            return
        }

        #expect(response.id == .int(1))
        #expect(response.error.code == -32601)
        #expect(response.error.message == Self.unsupportedMessage)
    }

    @Test("Server without resources rejects resources/unsubscribe")
    func nonResourceServerRejectsUnsubscribe() async throws {
        let calculator = Calculator()

        guard let message = await calculator.handleMessage(subscribeRequest(method: "resources/unsubscribe")) else {
            Issue.record("Expected a response message")
            return
        }
        guard case .errorResponse(let response) = message else {
            Issue.record("Expected errorResponse case")
            return
        }

        #expect(response.error.code == -32601)
        #expect(response.error.message == Self.unsupportedMessage)
    }

    @Test("Server with resources passes the capability guard")
    func resourceServerPassesCapabilityGuard() async throws {
        let server = ResourceTestServer()

        guard let message = await server.handleMessage(subscribeRequest(method: "resources/subscribe")) else {
            Issue.record("Expected a response message")
            return
        }
        guard case .errorResponse(let response) = message else {
            Issue.record("Expected errorResponse case")
            return
        }

        // It gets past the capability guard and only fails because no session is
        // bound in this unit-test task — proving the guard discriminates by
        // resource availability, not blanket rejection.
        #expect(response.error.message != Self.unsupportedMessage)
        #expect(response.error.code == -32603)
    }
}
