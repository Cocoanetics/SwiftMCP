#if Server
import Foundation

/// A modern `subscriptions/listen` stream. Keyed by its stream, not by a session:
/// the ephemeral session behind it exists only to carry the SSE stream.
struct ListenSubscription: Sendable {
    let sessionID: UUID
    let subscriptionID: JSONRPCID
    let filter: SubscriptionFilter
}

extension SessionManager {
    /// Open a listen stream: acknowledge it first, then start routing matching
    /// notifications to it. Returns `nil` when the session is already gone.
    func openListenStream(
        for session: Session,
        subscriptionID: JSONRPCID,
        requested: SubscriptionFilter,
        honored: SubscriptionFilter
    ) async -> (AsyncStream<Data>, StreamRouteResponseInfo)? {
        guard let opened = await createStream(for: session, kind: .request, resumable: false) else {
            return nil
        }
        let streamID = opened.1.streamID

        // The acknowledgement precedes every other message on the subscription:
        // the subscription is registered only once it has been queued.
        let acknowledgement = JSONRPCMessage.notification(
            method: "notifications/subscriptions/acknowledged",
            params: .object([
                "_meta": .object([MCPMetaKey.subscriptionId: subscriptionID.jsonValue]),
                "notifications": honored.jsonValue
            ])
        )
        _ = try? await sendJSONRPC(acknowledgement, to: streamID)

        guard streamMeta[streamID] != nil else {
            return nil
        }
        listenSubscriptions[streamID] = ListenSubscription(
            sessionID: session.id, subscriptionID: subscriptionID, filter: honored
        )
        return opened
    }

    /// Tear down a listen stream whose client went away: the subscription and its
    /// ephemeral session (with the stream) are removed.
    func endListenStream(streamID: UUID) async {
        guard let subscription = listenSubscriptions.removeValue(forKey: streamID) else {
            return
        }
        await removeSession(id: subscription.sessionID)
    }

    /// Send an SSE comment on every listen stream so idle connections stay open.
    func sendListenKeepAlive() async {
        for streamID in Array(listenSubscriptions.keys) {
            _ = await sendComment("keep-alive", to: streamID)
        }
    }

    /// End every listen stream gracefully with the empty `subscriptions/listen` result.
    func closeListenStreams() async {
        for (streamID, subscription) in listenSubscriptions {
            listenSubscriptions.removeValue(forKey: streamID)
            let result = JSONRPCMessage.response(
                id: subscription.subscriptionID,
                result: [
                    "resultType": .string("complete"),
                    "_meta": .object([MCPMetaKey.subscriptionId: subscription.subscriptionID.jsonValue])
                ]
            )
            _ = try? await sendJSONRPC(result, to: streamID)
            await finishStream(streamID: streamID)
            await removeSession(id: subscription.sessionID)
        }
    }

    /// Deliver a notification to every listen stream whose filter accepts it, tagged
    /// with the stream's subscription id.
    func deliverToListeners(
        method: String,
        params: JSONDictionary = [:],
        where accepts: (SubscriptionFilter) -> Bool
    ) async {
        for (streamID, subscription) in listenSubscriptions where accepts(subscription.filter) {
            var tagged = params
            var meta = tagged["_meta"]?.dictionaryValue ?? [:]
            meta[MCPMetaKey.subscriptionId] = subscription.subscriptionID.jsonValue
            tagged["_meta"] = .object(meta)
            let notification = JSONRPCMessage.notification(method: method, params: .object(tagged))
            _ = try? await sendJSONRPC(notification, to: streamID)
        }
    }
}

extension JSONRPCID {
    /// The id as a JSON value, for the `subscriptionId` `_meta` key.
    var jsonValue: JSONValue {
        switch self {
        case .integer(let value): return .integer(value)
        case .string(let value): return .string(value)
        }
    }
}
#endif
