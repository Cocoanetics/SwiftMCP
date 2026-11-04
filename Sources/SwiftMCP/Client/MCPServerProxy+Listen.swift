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
        let hadListen = listenTask != nil
        if case .sse = config {
            listenTask?.cancel()
        }
        listenTask = nil
        guard negotiatedEra == .modern, !isDisconnecting else {
            return
        }
        let filter: JSONValue
        if let current = listenFilter() {
            filter = current
        } else {
            // HTTP tears down its old subscription by cancelling the SSE stream.
            // A line transport has no stream to close, so supersede its stored
            // filter with an acknowledged, one-shot empty listen.
            guard hadListen else { return }
            if case .sse = config { return }
            filter = .object([:])
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
        failListenAcknowledgements(
            upTo: listenGeneration,
            with: .communicationError("subscriptions/listen was cancelled")
        )
    }

    /// Waits until the server acknowledged the current listen subscription (its
    /// filter is in effect), the attempt ended, or a timeout passed — so a
    /// modern `subscribeResource` returns only once updates can arrive.
    internal func awaitListenAcknowledgement() async throws -> SubscriptionFilter {
        let generation = listenGeneration
        if let result = listenAcknowledgementResults[generation] {
            return try result.get()
        }
        guard listenTask != nil else {
            throw MCPServerProxyError.communicationError("subscriptions/listen was not started")
        }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.listenAcknowledgementTimeout)
            await self?.completeListenAcknowledgement(
                generation: generation,
                result: .failure(.communicationError("Timed out waiting for subscriptions/listen acknowledgement"))
            )
        }
        return try await withCheckedThrowingContinuation { continuation in
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
        guard let honored = SubscriptionFilter(notification.params?["notifications"]) else {
            completeListenAcknowledgement(
                generation: generation,
                result: .failure(.communicationError("Invalid subscriptions/listen acknowledgement"))
            )
            return
        }
        completeListenAcknowledgement(generation: generation, result: .success(honored))
    }

    private func completeListenAcknowledgement(
        generation: Int,
        result: Result<SubscriptionFilter, MCPServerProxyError>
    ) {
        guard listenAcknowledgementResults[generation] == nil else { return }
        if generation >= (listenAcknowledgementResults.keys.max() ?? generation) {
            listenAcknowledgementResults = listenAcknowledgementResults.filter { $0.key >= generation }
        }
        listenAcknowledgementResults[generation] = result
        if let waiters = listenAcknowledgementWaiters.removeValue(forKey: generation), !waiters.isEmpty {
            for continuation in waiters {
                switch result {
                case .success(let filter):
                    continuation.resume(returning: filter)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            return
        }
    }

    private func failListenAcknowledgements(upTo generation: Int, with error: MCPServerProxyError) {
        for waiting in listenAcknowledgementWaiters.keys where waiting <= generation {
            for continuation in listenAcknowledgementWaiters.removeValue(forKey: waiting) ?? [] {
                continuation.resume(throwing: error)
            }
        }
        listenAcknowledgementResults = listenAcknowledgementResults.filter { $0.key > generation }
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
            switch await runListenAttempt(filter: filter, generation: generation) {
            case .stop:
                return
            case .retry(let resetDelay):
                if resetDelay {
                    retryDelay = 1_000_000_000
                }
            }
            try? await Task.sleep(nanoseconds: retryDelay)
            retryDelay = min(retryDelay * 2, Self.maxListenRetryDelay)
        }
    }

    private enum ListenAttemptResult {
        case stop
        case retry(resetDelay: Bool)
    }

    private func runListenAttempt(filter: JSONValue, generation: Int) async -> ListenAttemptResult {
        let requestID = nextRequestID()
        let request = JSONRPCMessage.request(
            id: requestID,
            method: "subscriptions/listen",
            params: .object(["notifications": filter])
        )
        recordListenRequest(requestID, generation: generation)
        defer { finishListenRequest(requestID, generation: generation) }
        do {
            let response = try await send(request)
            if case .errorResponse(let error) = response {
                logger.warning("[MCP] subscriptions/listen rejected: \(error.error.message)")
                completeListenAcknowledgement(
                    generation: generation,
                    result: .failure(typedModernError(error.error)
                        ?? .communicationError(error.error.message))
                )
                return .stop
            }
            guard case .sse = config else { return .stop }
            return .retry(resetDelay: true)
        } catch {
            completeListenAcknowledgement(
                generation: generation,
                result: .failure(error as? MCPServerProxyError
                    ?? .communicationError(error.localizedDescription))
            )
            guard case .sse = config, isCurrentListen(generation) else { return .stop }
            if case MCPServerProxyError.httpStatus(let status, _) = error, [404, 405].contains(status) {
                logger.warning("[MCP] Server does not support subscriptions/listen (HTTP \(status))")
                return .stop
            }
            logger.info("[MCP] subscriptions/listen stream ended: \(error.localizedDescription); re-opening")
            return .retry(resetDelay: false)
        }
    }

    private func recordListenRequest(_ requestID: JSONRPCID, generation: Int) {
        if case .sse = config {
            listenRequestGenerations[requestID] = generation
        } else {
            lineListenAcknowledgementQueue.append(generation)
        }
    }

    private func finishListenRequest(_ requestID: JSONRPCID, generation: Int) {
        listenRequestGenerations[requestID] = nil
        lineListenAcknowledgementQueue.removeAll { $0 == generation }
        completeListenAcknowledgement(
            generation: generation,
            result: .failure(.communicationError("subscriptions/listen ended before acknowledgement"))
        )
    }
}
#endif
