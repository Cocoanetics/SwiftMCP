#if Server
import Foundation
import Testing
@testable import SwiftMCP

#if canImport(Glibc)
import Glibc
private let streamSocket = Int32(SOCK_STREAM.rawValue)
#elseif canImport(Musl)
import Musl
private let streamSocket = SOCK_STREAM
#elseif canImport(Bionic)
import Bionic
private let streamSocket = SOCK_STREAM
#else
import Darwin
private let streamSocket = SOCK_STREAM
#endif

/// One request seen by ``LocalWebhookReceiver``.
struct ReceivedWebhook: Sendable {
    let headers: [String: String]
    let body: Data
}

/// A minimal HTTP/1.1 receiver on an ephemeral loopback port.
final class LocalWebhookReceiver: @unchecked Sendable {
    typealias Handler = @Sendable (Int, ReceivedWebhook) -> (status: Int, headers: [String: String])

    private let lock = NSLock()
    private var received: [ReceivedWebhook] = []
    private var descriptor: Int32 = -1
    private let handler: Handler
    let port: Int

    var requests: [ReceivedWebhook] { lock.lock(); defer { lock.unlock() }; return received }

    init(handler: @escaping Handler) throws {
        self.handler = handler
        let socketFD = socket(AF_INET, streamSocket, 0)
        guard socketFD >= 0 else { throw POSIXError(.EIO) }
        var reuse: Int32 = 1
        setsockopt(socketFD, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = 0
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, listen(socketFD, 16) == 0 else { close(socketFD); throw POSIXError(.EADDRINUSE) }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(socketFD, $0, &length) }
        }
        self.port = Int(UInt16(bigEndian: address.sin_port))
        self.descriptor = socketFD
        Thread.detachNewThread { [self] in serve(socketFD) }
    }

    func stop() {
        lock.lock()
        let listener = descriptor
        descriptor = -1
        lock.unlock()
        if listener >= 0 { shutdown(listener, SHUT_RDWR); close(listener) }
    }

    private func serve(_ listener: Int32) {
        while true {
            let connection = accept(listener, nil, nil)
            guard connection >= 0 else { return }
            handle(connection)
            close(connection)
        }
    }

    private func handle(_ connection: Int32) {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        let separator = Data("\r\n\r\n".utf8)
        while data.range(of: separator) == nil {
            let count = read(connection, &buffer, buffer.count)
            if count <= 0 { return }
            data.append(contentsOf: buffer[0..<count])
        }
        let split = data.range(of: separator)!
        let head = String(bytes: data[..<split.lowerBound], encoding: .utf8) ?? ""
        var headers: [String: String] = [:]
        for line in head.components(separatedBy: "\r\n").dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[line[..<colon].lowercased()] = value
        }
        var body = Data(data[split.upperBound...])
        let expected = Int(headers["content-length"] ?? "") ?? 0
        while body.count < expected {
            let count = read(connection, &buffer, buffer.count)
            if count <= 0 { break }
            body.append(contentsOf: buffer[0..<count])
        }

        let request = ReceivedWebhook(headers: headers, body: body)
        lock.lock()
        received.append(request)
        let number = received.count
        lock.unlock()

        let (status, extra) = handler(number, request)
        var response = "HTTP/1.1 \(status) X\r\nContent-Length: 0\r\nConnection: close\r\n"
        for (name, value) in extra { response += "\(name): \(value)\r\n" }
        response += "\r\n"
        let bytes = Array(response.utf8)
        _ = write(connection, bytes, bytes.count)
    }
}

/// Sends through the real `URLSession` transport, but to the local receiver
/// instead of the (non-routable) callback host.
private struct LoopbackTransport: MCPWebhookTransport {
    let port: Int

    func post(
        url: URL, headers: [String: String], body: Data, timeout: TimeInterval
    ) async throws -> MCPWebhookResponse {
        let local = URL(string: "http://127.0.0.1:\(port)\(url.path)")!
        return try await URLSessionWebhookTransport().post(url: local, headers: headers, body: body, timeout: timeout)
    }
}

@MCPServer(name: "DeliveryTestServer", version: "1.0")
actor DeliveryTestServer {
    let store: any MCPEventSubscriptionStore
    let configuration: MCPEventDeliveryConfiguration

    init(store: any MCPEventSubscriptionStore, configuration: MCPEventDeliveryConfiguration) {
        self.store = store
        self.configuration = configuration
    }

    nonisolated var eventSubscriptionStore: any MCPEventSubscriptionStore { store }
    nonisolated var eventDeliveryConfiguration: MCPEventDeliveryConfiguration { configuration }

    /// A build finished.
    ///
    /// - Parameter project: Only builds of this project.
    @MCPEvent(delivery: ["webhook"])
    func buildFinished(project: String? = nil) -> String { "" }
}

@Suite("MCPEvent: webhook delivery engine and emit")
struct MCPEventDeliveryTests {
    private static let url = "https://hooks.example.com/hook"
    private let secret = WebhookSigner.generateSecret()
    private let publicResolver: WebhookURLPolicy.Resolver = { _ in ["93.184.216.34"] }

    private func configuration(
        port: Int,
        resolver: WebhookURLPolicy.Resolver? = nil,
        delays: HTTPTransportBox<[TimeInterval]> = .init([]),
        maxAttempts: Int = 4
    ) -> MCPEventDeliveryConfiguration {
        MCPEventDeliveryConfiguration(
            resolver: resolver ?? publicResolver,
            transport: LoopbackTransport(port: port),
            maxAttempts: maxAttempts,
            initialBackoff: 1,
            jitter: { 1 },
            sleep: { delay in delays.modify { $0.append(delay) } }
        )
    }

    private func makeServer(
        port: Int, resolver: WebhookURLPolicy.Resolver? = nil, delays: HTTPTransportBox<[TimeInterval]> = .init([])
    ) -> DeliveryTestServer {
        DeliveryTestServer(
            store: MCPInMemoryEventSubscriptionStore(),
            configuration: configuration(port: port, resolver: resolver, delays: delays)
        )
    }

    private func subscribe(
        _ server: DeliveryTestServer, project: String = "A", token: String = "alice", unsubscribe: Bool = false
    ) async throws -> String? {
        let arguments: JSONValue = .object(["project": .string(project)])
        let delivery = EventsWebhookDelivery(url: Self.url, secret: unsubscribe ? nil : secret)
        let method = unsubscribe ? "events/unsubscribe" : "events/subscribe"
        let name = "buildFinished"
        var params = unsubscribe
            ? try JSONDictionary(
                encoding: EventsUnsubscribeParams(name: name, arguments: arguments, delivery: delivery)
            )
            : try JSONDictionary(
                encoding: EventsSubscribeParams(name: name, arguments: arguments, delivery: delivery)
            )
        params["_meta"] = .object([MCPMetaKey.protocolVersion: .string("2026-07-28"), "accessToken": .string(token)])
        let message = JSONRPCMessage.request(id: 1, method: method, params: .object(params))
        let response = try #require(await RequestContext(message: message).work { _ in
            await server.handleMessage(message)
        })
        guard case .response(let data) = response, let result = data.result else { return nil }
        return try? result.decoded(EventsSubscribeResult.self).id
    }

    private func emitBuild(
        _ server: DeliveryTestServer, project: String = "A", eventId: String? = nil
    ) async throws -> [MCPEventDeliveryOutcome] {
        try await server.emit(
            "buildFinished", "ok", eventId: eventId, attributes: .object(["project": .string(project)])
        )
    }

    @Test("Subscribe, emit, verify signature and dedup id; after unsubscribe nothing is delivered")
    func endToEnd() async throws {
        let receiver = try LocalWebhookReceiver { _, _ in (200, [:]) }
        defer { receiver.stop() }
        let server = makeServer(port: receiver.port)

        let id = try #require(try await subscribe(server))
        _ = try await subscribe(server, project: "B")

        let outcomes = try await emitBuild(server, eventId: "evt_1")
        #expect(outcomes == [MCPEventDeliveryOutcome(
            subscriptionId: id, eventId: "evt_1", status: .delivered, attempts: 1, statusCode: 200
        )])

        let request = try #require(receiver.requests.first)
        #expect(receiver.requests.count == 1, "only the matching subscription receives it")
        try WebhookSigner(secret: secret).verify(headers: request.headers, body: request.body)
        #expect(request.headers["webhook-id"] == "evt_1")
        #expect(request.headers["x-mcp-subscription-id"] == id)
        let occurrence = try JSONDecoder().decode(MCPEventOccurrence.self, from: request.body)
        #expect(occurrence.eventId == "evt_1")
        #expect(occurrence.name == "buildFinished")
        #expect(occurrence.data == .string("ok"))

        _ = try await subscribe(server, unsubscribe: true)
        #expect(try await emitBuild(server).isEmpty)
        #expect(receiver.requests.count == 1)
    }

    @Test("A flaky receiver is retried with backoff and Retry-After, keeping the webhook-id")
    func flakyReceiver() async throws {
        let receiver = try LocalWebhookReceiver { number, _ in
            number < 3 ? (503, number == 1 ? ["Retry-After": "5"] : [:]) : (200, [:])
        }
        defer { receiver.stop() }
        let delays = HTTPTransportBox<[TimeInterval]>([])
        let server = makeServer(port: receiver.port, delays: delays)
        _ = try await subscribe(server)

        let outcome = try #require(try await emitBuild(server, eventId: "evt_retry").first)
        #expect(outcome.status == .delivered)
        #expect(outcome.attempts == 3)
        #expect(delays.value == [5, 2], "Retry-After outranks the 1 s backoff; the second wait is the doubled backoff")

        let requests = receiver.requests
        #expect(requests.count == 3)
        #expect(Set(requests.compactMap { $0.headers["webhook-id"] }) == ["evt_retry"])
        #expect(Set(requests.map(\.body)).count == 1, "the body is serialized once")
        for request in requests {
            try WebhookSigner(secret: secret).verify(headers: request.headers, body: request.body)
        }
    }

    @Test("An offline receiver exhausts its attempts and reports failure")
    func offlineReceiver() async throws {
        let receiver = try LocalWebhookReceiver { _, _ in (200, [:]) }
        let port = receiver.port
        receiver.stop()
        let delays = HTTPTransportBox<[TimeInterval]>([])
        let server = DeliveryTestServer(
            store: MCPInMemoryEventSubscriptionStore(),
            configuration: configuration(port: port, delays: delays, maxAttempts: 3)
        )
        _ = try await subscribe(server)

        let outcome = try #require(try await emitBuild(server).first)
        #expect(outcome.status == .failed)
        #expect(outcome.attempts == 3)
        #expect(outcome.error != nil)
        #expect(delays.value.count == 2)
    }

    @Test("410, 413, other 4xx and redirects are not retried or followed")
    func permanentRejections() async throws {
        for status in [410, 413, 400, 302] {
            let receiver = try LocalWebhookReceiver { _, _ in
                (status, status == 302 ? ["Location": "http://127.0.0.1:1/elsewhere"] : [:])
            }
            defer { receiver.stop() }
            let server = makeServer(port: receiver.port)
            let id = try #require(try await subscribe(server))

            let outcome = try #require(try await emitBuild(server).first)
            #expect(outcome.status == .rejected, "\(status)")
            #expect(outcome.attempts == 1, "\(status)")
            #expect(outcome.statusCode == status)
            #expect(receiver.requests.count == 1, "\(status)")
            // The subscription itself survives a refused delivery.
            #expect(try await server.store.subscription(id: id, now: Date()) != nil, "\(status)")
        }
    }

    @Test("A callback that resolves to a private address is never contacted")
    func blockedAddress() async throws {
        let receiver = try LocalWebhookReceiver { _, _ in (200, [:]) }
        defer { receiver.stop() }
        let server = DeliveryTestServer(
            store: MCPInMemoryEventSubscriptionStore(),
            configuration: configuration(port: receiver.port, resolver: { _ in ["10.0.0.5"] })
        )
        _ = try await subscribe(server)

        let outcome = try #require(try await emitBuild(server).first)
        #expect(outcome.status == .failed)
        #expect(outcome.attempts == 0)
        #expect(receiver.requests.isEmpty)
    }

    @Test("Unknown events and payloads that violate the schema are refused")
    func emitValidation() async throws {
        let server = makeServer(port: 1)
        await #expect(throws: MCPEventEmitError.unknownEvent("nope")) { try await server.emit("nope", "x") }
        do {
            _ = try await server.emit("buildFinished", 42)
            Issue.record("a number is not a string payload")
        } catch let error as MCPEventEmitError {
            guard case .invalidPayload = error else {
                Issue.record("unexpected \(error)")
                return
            }
        }
    }
}
#endif
