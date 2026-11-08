#if Server
//
//  MCPEventDelivery.swift
//  SwiftMCP
//
//  Webhook delivery engine for `events/*`: signs each occurrence with
//  Standard Webhooks, sends it through the SSRF policy without following
//  redirects, retries transient failures with backoff and reports an outcome
//  per subscription. Phase 4 of #204.
//

import Foundation
import SwiftCross
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Bionic)
import Bionic
#endif

/// One event occurrence as POSTed to a subscriber's webhook.
public struct MCPEventOccurrence: Codable, Sendable, Equatable {
    /// Stable identifier, also sent as `webhook-id`; receivers deduplicate on it.
    public let eventId: String
    public let name: String
    /// ISO 8601 time the event occurred.
    public let timestamp: String
    public let data: JSONValue
    public let cursor: String?

    public init(eventId: String, name: String, timestamp: String, data: JSONValue, cursor: String? = nil) {
        self.eventId = eventId
        self.name = name
        self.timestamp = timestamp
        self.data = data
        self.cursor = cursor
    }
}

/// How delivery to one subscription ended.
public enum MCPEventDeliveryStatus: String, Codable, Sendable, Equatable {
    /// The receiver answered 2xx.
    case delivered
    /// The receiver refused the delivery and it was not retried (for example 410, 413 or another 4xx).
    case rejected
    /// The URL was blocked, or every attempt failed transiently.
    case failed
}

/// Result of delivering one occurrence to one subscription.
public struct MCPEventDeliveryOutcome: Codable, Sendable, Equatable {
    public let subscriptionId: String
    public let eventId: String
    public let status: MCPEventDeliveryStatus
    /// Requests actually sent; `0` if the URL was blocked before any attempt.
    public let attempts: Int
    public let statusCode: Int?
    public let error: String?

    public init(
        subscriptionId: String,
        eventId: String,
        status: MCPEventDeliveryStatus,
        attempts: Int,
        statusCode: Int? = nil,
        error: String? = nil
    ) {
        self.subscriptionId = subscriptionId
        self.eventId = eventId
        self.status = status
        self.attempts = attempts
        self.statusCode = statusCode
        self.error = error
    }
}

/// The part of a webhook response the engine looks at.
public struct MCPWebhookResponse: Sendable, Equatable {
    public let statusCode: Int
    /// Parsed `Retry-After`, in seconds.
    public let retryAfter: TimeInterval?

    public init(statusCode: Int, retryAfter: TimeInterval? = nil) {
        self.statusCode = statusCode
        self.retryAfter = retryAfter
    }
}

/// Tunables of webhook delivery. Defaults are safe: HTTPS only, public addresses
/// only, a 10 s timeout and four attempts.
public struct MCPEventDeliveryConfiguration: Sendable {
    public var urlPolicy: WebhookURLPolicy
    public var resolver: WebhookURLPolicy.Resolver
    public var transport: any MCPWebhookTransport
    /// Total tries per delivery, the first included.
    public var maxAttempts: Int
    public var initialBackoff: TimeInterval
    public var maxBackoff: TimeInterval
    /// Per-request timeout.
    public var timeout: TimeInterval
    /// Largest accepted body; bigger occurrences are refused by `emit` (receivers answer 413).
    public var maxBodyBytes: Int
    /// Deliveries of one `emit` running at once.
    public var maxConcurrentDeliveries: Int
    /// Scales each backoff; defaults to a random factor in 0.5...1.
    public var jitter: @Sendable () -> Double
    public var sleep: @Sendable (TimeInterval) async -> Void
    public var now: @Sendable () -> Date

    public init(
        urlPolicy: WebhookURLPolicy = WebhookURLPolicy(),
        resolver: @escaping WebhookURLPolicy.Resolver = WebhookURLPolicy.systemResolver,
        transport: any MCPWebhookTransport = URLSessionWebhookTransport(),
        maxAttempts: Int = 4,
        initialBackoff: TimeInterval = 1,
        maxBackoff: TimeInterval = 60,
        timeout: TimeInterval = 10,
        maxBodyBytes: Int = 256 * 1024,
        maxConcurrentDeliveries: Int = 16,
        jitter: @escaping @Sendable () -> Double = { Double.random(in: 0.5...1) },
        sleep: @escaping @Sendable (TimeInterval) async -> Void = {
            try? await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000))
        },
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.urlPolicy = urlPolicy
        self.resolver = resolver
        self.transport = transport
        self.maxAttempts = max(1, maxAttempts)
        self.initialBackoff = initialBackoff
        self.maxBackoff = maxBackoff
        self.timeout = timeout
        self.maxBodyBytes = maxBodyBytes
        self.maxConcurrentDeliveries = max(1, maxConcurrentDeliveries)
        self.jitter = jitter
        self.sleep = sleep
        self.now = now
    }
}

/// Delivers one occurrence to one subscription.
enum MCPEventDeliveryEngine {
    static let subscriptionIdHeader = "X-MCP-Subscription-Id"

    /// How a response status is treated.
    private enum Disposition { case delivered, retry, rejected }

    private static func disposition(of statusCode: Int) -> Disposition {
        switch statusCode {
        case 200..<300: return .delivered
        // 410 and 413 are explicit "do not retry"; the subscription stays intact.
        case 410, 413: return .rejected
        case 408, 425, 429, 500..<600: return .retry
        default: return .rejected
        }
    }

    static func deliver(
        eventId: String,
        body: Data,
        to subscription: MCPEventSubscription,
        configuration: MCPEventDeliveryConfiguration
    ) async -> MCPEventDeliveryOutcome {
        func outcome(
            _ status: MCPEventDeliveryStatus, _ attempts: Int, _ code: Int? = nil, _ error: String? = nil
        ) -> MCPEventDeliveryOutcome {
            MCPEventDeliveryOutcome(
                subscriptionId: subscription.id, eventId: eventId,
                status: status, attempts: attempts, statusCode: code, error: error
            )
        }

        guard let signer = try? WebhookSigner(secret: subscription.secret) else {
            return outcome(.failed, 0, nil, "invalid signing secret")
        }
        guard let url = URL(string: subscription.url) else { return outcome(.failed, 0, nil, "invalid URL") }

        var lastStatus: Int?
        var lastError = "no attempt made"
        for attempt in 1...configuration.maxAttempts {
            var retryAfter: TimeInterval?
            do {
                // Re-vetted on every attempt: DNS answers can change between retries.
                _ = try await configuration.urlPolicy.validate(subscription.url, resolver: configuration.resolver)
            } catch {
                return outcome(.failed, attempt - 1, lastStatus, "URL rejected: \(error)")
            }

            // The webhook-id is the event id on every attempt; timestamp and signature are fresh.
            var headers = signer.headers(
                id: eventId, timestamp: Int(configuration.now().timeIntervalSince1970), body: body
            )
            headers[subscriptionIdHeader] = subscription.id
            headers["Content-Type"] = "application/json"

            do {
                let response = try await configuration.transport.post(
                    url: url, headers: headers, body: body, timeout: configuration.timeout
                )
                lastStatus = response.statusCode
                lastError = "HTTP \(response.statusCode)"
                switch disposition(of: response.statusCode) {
                case .delivered: return outcome(.delivered, attempt, response.statusCode)
                case .rejected: return outcome(.rejected, attempt, response.statusCode, lastError)
                case .retry: retryAfter = response.retryAfter
                }
            } catch {
                lastStatus = nil
                lastError = "\(error)"
            }

            if attempt < configuration.maxAttempts {
                let backoff = min(configuration.maxBackoff, configuration.initialBackoff * pow(2, Double(attempt - 1)))
                let delay = max(backoff * configuration.jitter(), min(retryAfter ?? 0, configuration.maxBackoff))
                await configuration.sleep(delay)
            }
        }
        return outcome(.failed, configuration.maxAttempts, lastStatus, lastError)
    }
}

/// Why `emit` refused an occurrence.
public enum MCPEventEmitError: Error, Equatable, Sendable, CustomStringConvertible {
    case unknownEvent(String)
    case invalidPayload(String)
    case payloadTooLarge(Int)

    public var description: String {
        switch self {
        case .unknownEvent(let name): return "Unknown event: \(name)"
        case .invalidPayload(let reason): return "Payload does not match the event's payloadSchema: \(reason)"
        case .payloadTooLarge(let size): return "Event body of \(size) bytes exceeds the delivery limit"
        }
    }
}

extension MCPEventProviding {
    /// Publishes an event to every matching webhook subscription.
    ///
    /// The payload is encoded, checked against the event's `payloadSchema`,
    /// serialized once and sent, signed, to each active subscription whose filter
    /// matches. The call returns when every delivery has finished, retries
    /// included (up to `maxAttempts` with backoff), so wrap it in a `Task` where
    /// that wait is unwanted.
    ///
    /// A subscription matches when each non-null entry of its filter equals the
    /// same-named entry of `attributes`; `attributes` defaults to the top-level
    /// fields of an object payload. A payload that is not an object, and has no
    /// `attributes`, matches only subscriptions with an empty filter.
    ///
    /// - Parameters:
    ///   - eventId: Stable id used for deduplication; generated when omitted.
    ///     Pass the upstream's own id so repeated surfacing of one event collapses.
    /// - Returns: One outcome per matched subscription.
    @discardableResult
    public func emit<Payload: Encodable>(
        _ name: String,
        _ payload: Payload,
        eventId: String? = nil,
        attributes: JSONValue? = nil,
        cursor: String? = nil
    ) async throws -> [MCPEventDeliveryOutcome] {
        guard let metadata = await mcpEventMetadata.first(where: { $0.name == name }) else {
            throw MCPEventEmitError.unknownEvent(name)
        }
        let configuration = eventDeliveryConfiguration

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data: JSONValue
        do {
            data = try JSONDecoder().decode(JSONValue.self, from: encoder.encode(payload))
            try EventFilterValidator.validate(data, against: metadata.descriptor.payloadSchema)
        } catch {
            throw MCPEventEmitError.invalidPayload("\(error)")
        }

        let now = configuration.now()
        let id = eventId ?? "evt_" + UUID().uuidString.lowercased()
        let occurrence = MCPEventOccurrence(
            eventId: id, name: name, timestamp: ISO8601DateFormatter().string(from: now), data: data, cursor: cursor
        )
        let bodyEncoder = JSONEncoder()
        bodyEncoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let body = try bodyEncoder.encode(occurrence)
        guard body.count <= configuration.maxBodyBytes else { throw MCPEventEmitError.payloadTooLarge(body.count) }

        let store = eventSubscriptionStore
        _ = try await store.purgeExpired(now: now)
        let attributes = attributes ?? data
        let targets = try await store.subscriptions(principal: nil, now: now).filter {
            $0.name == name && Self.filter($0.arguments, matches: attributes)
        }

        return await withTaskGroup(of: MCPEventDeliveryOutcome.self) { group in
            var outcomes: [MCPEventDeliveryOutcome] = []
            var running = 0
            for subscription in targets {
                if running >= configuration.maxConcurrentDeliveries, let outcome = await group.next() {
                    outcomes.append(outcome)
                    running -= 1
                }
                group.addTask {
                    await MCPEventDeliveryEngine.deliver(
                        eventId: id, body: body, to: subscription, configuration: configuration
                    )
                }
                running += 1
            }
            for await outcome in group { outcomes.append(outcome) }
            return outcomes.sorted { $0.subscriptionId < $1.subscriptionId }
        }
    }

    private static func filter(_ filter: JSONValue, matches attributes: JSONValue) -> Bool {
        guard case .object(let wanted) = filter else { return true }
        let present = wanted.filter { $0.value != .null }
        if present.isEmpty { return true }
        guard case .object(let actual) = attributes else { return false }
        return present.allSatisfy { actual[$0.key] == $0.value }
    }
}
#endif
