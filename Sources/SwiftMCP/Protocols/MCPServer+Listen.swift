import Foundation

// MARK: - subscriptions/listen on line transports (MCP 2026-07-28)
extension MCPServer {

    /// Handles a modern `subscriptions/listen` that reached the dispatcher — on a
    /// line transport (stdio, TCP, in-process); the HTTP transport answers it with
    /// its own long-lived SSE stream before dispatch. The connection carries the
    /// notifications, so the subscription is recorded on the session and the
    /// request stays open: no response now (line transports dispatch requests in
    /// order, so waiting here would stall the connection), the empty result once
    /// a newer listen request supersedes it.
    func handleLineSubscriptionsListen(_ request: JSONRPCMessage.JSONRPCRequestData) async -> JSONRPCMessage? {
        guard await RequestContext.current?.modernProfile?.has(.subscriptionsListen) == true,
              let session = Session.current else {
            return JSONRPCMessage.errorResponse(
                id: request.id,
                error: .init(code: -32601, message: "Method not found")
            )
        }
        guard let requested = SubscriptionFilter(request.params?["notifications"]) else {
            return JSONRPCMessage.errorResponse(
                id: request.id,
                error: .init(
                    code: -32602,
                    message: "Invalid params: 'notifications' must be a subscription filter object."
                )
            )
        }

        let honored = requested.honored(by: await buildServerCapabilities())
        let previous: LineListenSubscription?
        if honored.isEmpty {
            previous = await session.clearLineListen()
        } else {
            previous = await session.replaceLineListen(LineListenSubscription(id: request.id, filter: honored))
        }
        if let previous {
            try? await session.transport?.send(Self.listenCompletion(id: previous.id))
        }

        // The acknowledgement precedes every other message on the subscription.
        let acknowledgement = JSONRPCMessage.notification(
            method: "notifications/subscriptions/acknowledged",
            params: .object([
                "_meta": .object([MCPMetaKey.subscriptionId: request.id.jsonValue]),
                "notifications": honored.jsonValue
            ])
        )
        try? await session.transport?.send(acknowledgement)
        // On line transports an empty filter is a one-shot way to clear the
        // session's stored subscription. Acknowledge it, then complete it so no
        // useless request remains pending until disconnect.
        return honored.isEmpty ? Self.listenCompletion(id: request.id) : nil
    }

    /// The empty result that ends a listen subscription.
    static func listenCompletion(id: JSONRPCID) -> JSONRPCMessage {
        JSONRPCMessage.response(
            id: id,
            result: [
                "resultType": .string("complete"),
                "_meta": .object([MCPMetaKey.subscriptionId: id.jsonValue])
            ]
        )
    }
}
