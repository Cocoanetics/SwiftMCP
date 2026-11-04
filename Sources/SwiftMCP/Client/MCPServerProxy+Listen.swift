#if Client
import Foundation

/// Modern-era server pushes: one `subscriptions/listen` request replaces the
/// legacy general SSE stream and `resources/subscribe`. Its filter follows the
/// registered list-changed handlers and ``subscribedResourceURIs``; any change
/// re-opens it with the new filter.
extension MCPServerProxy {
    /// The most a broken HTTP listen stream waits before re-opening.
    private static let maxListenRetryDelay: UInt64 = 30_000_000_000

    /// How long a caller waits for the server to acknowledge a new filter.
    private static let listenAcknowledgementTimeout: UInt64 = 10_000_000_000

    /// The `notifications` filter of the listen request, or `nil` when there is
    /// nothing to listen for.
    internal func listenFilter() -> JSONValue? {
        var filter: JSONDictionary = [:]
        if notificationHandlers[NotificationMethod.toolsListChanged] != nil {
            filter["toolsListChanged"] = .bool(true)
        }
        if notificationHandlers[NotificationMethod.resourcesListChanged] != nil {
            filter["resourcesListChanged"] = .bool(true)
        }
        if notificationHandlers[NotificationMethod.promptsListChanged] != nil {
            filter["promptsListChanged"] = .bool(true)
        }
        if !subscribedResourceURIs.isEmpty {
            filter["resourceSubscriptions"] = .array(
                subscribedResourceURIs.map(\.absoluteString).sorted().map { .string($0) }
            )
        }
        return filter.isEmpty ? nil : .object(filter)
    }

    /// (Re-)opens the listen subscription for the current filter on a modern
    /// connection; a no-op on legacy ones. Over HTTP the previous stream is
    /// closed; on a line transport the server ends the previous request when the
    /// new one supersedes it.
    internal func refreshListenSubscription() {
        if case .sse = config {
            listenTask?.cancel()
        }
        listenTask = nil
        guard negotiatedEra == .modern, !isDisconnecting, let filter = listenFilter() else {
            return
        }
        listenGeneration += 1
        let generation = listenGeneration
        listenTask = Task { [weak self] in
            await self?.runListen(filter: filter, generation: generation)
        }
    }

    internal func cancelListenSubscription() {
        listenTask?.cancel()
        listenTask = nil
        listenGeneration += 1
        resumeListenWaiters(upTo: listenGeneration)
    }

    /// Waits until the server acknowledged the current listen subscription (its
    /// filter is in effect), the attempt ended, or a timeout passed — so a
    /// modern `subscribeResource` returns only once updates can arrive.
    internal func awaitListenAcknowledgement() async {
        let generation = listenGeneration
        guard listenTask != nil, acknowledgedListenGeneration < generation else {
            return
        }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.listenAcknowledgementTimeout)
            await self?.resumeListenWaiters(upTo: generation)
        }
        await withCheckedContinuation { continuation in
            listenAcknowledgementWaiters[generation, default: []].append(continuation)
        }
    }

    /// Records a `notifications/subscriptions/acknowledged` for one of our listen requests.
    internal func listenAcknowledged(_ notification: JSONRPCMessage.JSONRPCNotificationData) {
        let rawID = notification.params?["_meta"]?[MCPMetaKey.subscriptionId]
        let id: JSONRPCID? = rawID?.intValue.map { .integer($0) } ?? rawID?.stringValue.map { .string($0) }
        let generation: Int
        if let id, let byID = listenRequestGenerations[id] {
            generation = byID
        } else if !lineListenAcknowledgementQueue.isEmpty {
            generation = lineListenAcknowledgementQueue.removeFirst()
        } else {
            return
        }
        acknowledgedListenGeneration = max(acknowledgedListenGeneration, generation)
        resumeListenWaiters(upTo: generation)
    }

    private func resumeListenWaiters(upTo generation: Int) {
        for waiting in listenAcknowledgementWaiters.keys where waiting <= generation {
            for continuation in listenAcknowledgementWaiters.removeValue(forKey: waiting) ?? [] {
                continuation.resume()
            }
        }
    }

    private func isCurrentListen(_ generation: Int) -> Bool {
        !Task.isCancelled && generation == listenGeneration && negotiatedEra == .modern && !isDisconnecting
    }

    /// Holds one listen request open. A line transport's request ends only when
    /// it is superseded or the connection closes; an HTTP stream that drops is
    /// re-opened with backoff while the subscription is still current.
    private func runListen(filter: JSONValue, generation: Int) async {
        var retryDelay: UInt64 = 1_000_000_000
        while isCurrentListen(generation) {
            let requestID = nextRequestID()
            let request = JSONRPCMessage.request(
                id: requestID,
                method: "subscriptions/listen",
                params: .object(["notifications": filter])
            )
            if case .sse = config {
                listenRequestGenerations[requestID] = generation
            } else {
                lineListenAcknowledgementQueue.append(generation)
            }
            defer {
                listenRequestGenerations[requestID] = nil
                lineListenAcknowledgementQueue.removeAll { $0 == generation }
                resumeListenWaiters(upTo: generation)
            }
            do {
                let response = try await send(request)
                if case .errorResponse(let error) = response {
                    logger.warning("[MCP] subscriptions/listen rejected: \(error.error.message)")
                    return
                }
                guard case .sse = config else {
                    return
                }
                retryDelay = 1_000_000_000
            } catch {
                guard case .sse = config, isCurrentListen(generation) else {
                    return
                }
                if case MCPServerProxyError.httpStatus(let status, _) = error, [404, 405].contains(status) {
                    logger.warning("[MCP] Server does not support subscriptions/listen (HTTP \(status))")
                    return
                }
                logger.info("[MCP] subscriptions/listen stream ended: \(error.localizedDescription); re-opening")
            }
            try? await Task.sleep(nanoseconds: retryDelay)
            retryDelay = min(retryDelay * 2, Self.maxListenRetryDelay)
        }
    }
}
#endif
