import Foundation

/// A modern `subscriptions/listen` request on a line transport (stdio, TCP,
/// in-process). The connection itself carries the notifications, so the
/// subscription lives on the session rather than on a dedicated stream; a newer
/// listen request supersedes it.
struct LineListenSubscription: Sendable {
    let id: JSONRPCID
    let filter: SubscriptionFilter
}

extension Session {
    /// Starts `subscription`, returning the one it supersedes.
    func replaceLineListen(_ subscription: LineListenSubscription) -> LineListenSubscription? {
        let previous = lineListen
        lineListen = subscription
        return previous
    }

    /// Clears the active line listen, returning the request it superseded.
    func clearLineListen() -> LineListenSubscription? {
        let previous = lineListen
        lineListen = nil
        return previous
    }

    /// The notification to send for `method`. A session with a line listen
    /// subscription gets it only when the subscription's filter `accepts` it,
    /// tagged with the subscription id; any other session gets it untagged, as
    /// before. `nil` means the notification is filtered out.
    func listenNotification(
        method: String,
        params: JSONDictionary = [:],
        accepts: (SubscriptionFilter) -> Bool
    ) -> JSONRPCMessage? {
        guard let lineListen else {
            return .notification(method: method, params: params.isEmpty ? nil : .object(params))
        }
        guard accepts(lineListen.filter) else {
            return nil
        }
        var tagged = params
        var meta = tagged["_meta"]?.dictionaryValue ?? [:]
        meta[MCPMetaKey.subscriptionId] = lineListen.id.jsonValue
        tagged["_meta"] = .object(meta)
        return .notification(method: method, params: .object(tagged))
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
