#if Server
// Regression tests for the zombie-session defect (MissionControl incident,
// 2026-08-12): an SSE stream that is opened but never drained/bound could hold
// a session's primary-general slot forever, silently black-holing every
// broadcast while POSTs and the (other) live stream stayed healthy.
//
// The phases forge the black-hole states directly through SessionManager and
// assert that (1) undeliverable resource-updated broadcasts are counted
// instead of dropped silently, (2) registration rejects dead connections and
// starts the retention clock, and (3) the janitor reclaims never-bound streams
// after one retention interval so routing heals onto the live stream.
//
// One shared transport on purpose: each start/stop spins up (and tears down) a
// full event-loop group, and phases that need to outwait the retention
// interval would otherwise multiply that churn.

import Foundation
import Logging
import Testing
import SwiftCross
@testable import SwiftMCP

/// A non-SSE ``Transport``, standing in for ``TCPBonjourTransport`` (which
/// shares ``SessionManager`` but has no SSE streams): it records what the
/// session sends, and can be made unreachable to exercise the failure path.
final class NonSSERecordingTransport: Transport, @unchecked Sendable {
    let logger = Logger(label: "com.cocoanetics.SwiftMCP.RecordingTransport")
    private let sent = HTTPTransportBox<[String]>([])
    private let reachable = HTTPTransportBox<Bool>(true)

    var sentMessages: [String] { sent.value }
    func setReachable(_ value: Bool) { reachable.value = value }

    func start() async throws {}
    func run() async throws {}
    func stop() async throws {}

    func send(_ data: Data) async throws {
        guard reachable.value else {
            throw TransportError.bindingFailed("Client unreachable")
        }
        sent.modify { $0.append(String(data: data, encoding: .utf8) ?? "") }
    }
}

@Suite("Zombie-session regression", .serialized)
struct BroadcastZombieRegressionTests {

    /// `SessionManager` is shared with the TCP transport, whose sessions never
    /// create SSE streams. Broadcasts must therefore go out through each
    /// session's own transport, not through SSE stream routing — routing
    /// directly would silently drop every TCP client's notifications.
    @Test func nonSSETransportsStillReceiveResourceUpdated() async throws {
        // Both references must be held: `Session.transport` and
        // `SessionManager.transport` are weak.
        let transport = NonSSERecordingTransport()
        let manager = SessionManager(transport: transport)

        let session = await manager.session(id: UUID())
        await session.subscribeResource(uri: "push://tcp")

        await manager.broadcastResourceUpdated(uri: URL(string: "push://tcp")!)
        #expect(transport.sentMessages.count == 1)
        #expect(transport.sentMessages.first?.contains("notifications/resources/updated") == true)
        #expect(transport.sentMessages.first?.contains("push://tcp") == true)
        #expect(await manager.undeliverableBroadcastCount == 0)

        // An unreachable client is a counted drop, not a silent one.
        transport.setReachable(false)
        await manager.broadcastResourceUpdated(uri: URL(string: "push://tcp")!)
        #expect(transport.sentMessages.count == 1)
        #expect(await manager.undeliverableBroadcastCount == 1)

        // …and delivery recovers once the client is reachable again.
        transport.setReachable(true)
        await manager.broadcastResourceUpdated(uri: URL(string: "push://tcp")!)
        #expect(transport.sentMessages.count == 2)
        #expect(await manager.undeliverableBroadcastCount == 1)
    }

    @Test(.timeLimit(.minutes(3)))
    func zombieStreamStatesAreReclaimedCountedAndRejected() async throws {
        let (transport, baseURL) = try await HTTPTransportTestHelpers.startTransport(
            server: PushFixtureServer(), retentionInterval: 1.0
        )
        let mcpURL = baseURL.appendingPathComponent("mcp")
        let urlSession = URLSession(configuration: .ephemeral)

        try await assertUndeliverableBroadcastIsCounted(
            transport: transport, mcpURL: mcpURL, urlSession: urlSession
        )
        try await assertDeadConnectionRegistrationIsRejected(
            transport: transport, mcpURL: mcpURL, urlSession: urlSession
        )
        try await assertNeverBoundStreamIsReclaimedAndRoutingHeals(
            transport: transport, mcpURL: mcpURL, urlSession: urlSession
        )

        urlSession.invalidateAndCancel()
        try await transport.stop()
    }

    // MARK: - Phases

    /// A subscribed session with no routable general stream must be counted
    /// (and logged) instead of dropping the notification without a trace.
    private func assertUndeliverableBroadcastIsCounted(
        transport: HTTPSSETransport,
        mcpURL: URL,
        urlSession: URLSession
    ) async throws {
        let uri = "push://counting"
        let (sessionID, _) = try await initializeAndSubscribe(
            uri: uri, mcpURL: mcpURL, urlSession: urlSession
        )

        // No general stream was ever opened for this session.
        await transport.broadcastResourceUpdated(uri: URL(string: uri)!)
        await transport.broadcastResourceUpdated(uri: URL(string: uri)!)

        let manager = transport.sessionManager
        #expect(await manager.undeliverableBroadcastCount == 2)

        // Once a general stream connects, delivery must recover and the
        // counter must stop growing.
        let capture = try await openLiveGeneralStream(
            sessionID: sessionID, mcpURL: mcpURL, urlSession: urlSession
        )
        await transport.broadcastResourceUpdated(uri: URL(string: uri)!)
        #expect(await manager.undeliverableBroadcastCount == 2)
        let received = await HTTPTransportTestHelpers.waitForCondition {
            HTTPTransportTestHelpers.notificationEvent(
                capture.events.value, method: "notifications/resources/updated"
            ) != nil
        }
        #expect(received)

        capture.task.cancel()
    }

    /// Registering a connection that is already dead must fail and start the
    /// retention clock, instead of parking the stream in a live-looking state
    /// no cleanup ever reclaims.
    private func assertDeadConnectionRegistrationIsRejected(
        transport: HTTPSSETransport,
        mcpURL: URL,
        urlSession: URLSession
    ) async throws {
        let (sessionID, _) = try await HTTPTransportTestHelpers.initializeSession(
            url: mcpURL, urlSession: urlSession
        )
        let sessionUUID = try #require(UUID(uuidString: sessionID))
        let manager = transport.sessionManager

        let (_, info) = await manager.createStream(sessionID: sessionUUID, kind: .general)
        let token = await manager.register(
            connection: DeadSSEConnection(),
            sessionID: sessionUUID,
            streamID: info.streamID
        )
        #expect(token == nil, "a dead connection must not be registered")

        // The rejection started the retention clock: the stream must be gone
        // after one retention interval.
        try await Task.sleep(nanoseconds: 1_500_000_000)
        let streams = await manager.activeStreamIDs()
        #expect(!streams.contains(info.streamID))
        #expect(await manager.primaryGeneralStreamID(for: sessionUUID) != info.streamID)
    }

    /// A general stream that is opened but never drained or bound (e.g. its
    /// response was discarded, or the drain never started) steals the
    /// primary-general slot. The janitor must reclaim it after one retention
    /// interval so broadcasts heal back onto the live stream — before the fix
    /// this state survived forever.
    private func assertNeverBoundStreamIsReclaimedAndRoutingHeals(
        transport: HTTPSSETransport,
        mcpURL: URL,
        urlSession: URLSession
    ) async throws {
        let uri = "push://healing"
        let (sessionID, sessionUUID) = try await initializeAndSubscribe(
            uri: uri, mcpURL: mcpURL, urlSession: urlSession
        )
        let capture = try await openLiveGeneralStream(
            sessionID: sessionID, mcpURL: mcpURL, urlSession: urlSession
        )
        let manager = transport.sessionManager
        let liveStreamID = try #require(await manager.primaryGeneralStreamID(for: sessionUUID))

        // Forge the black hole: an SSE stream the route layer opened (claiming
        // the primary slot) whose response never gets drained or bound —
        // exactly what handleSSE produces when the adapter discards the
        // response or the drain dies before binding.
        let (_, abandonedInfo) = await manager.createStream(sessionID: sessionUUID, kind: .general)
        #expect(await manager.primaryGeneralStreamID(for: sessionUUID) == abandonedInfo.streamID)

        // While the abandoned stream holds the slot, broadcasts vanish into its
        // unconsumed buffer: the live stream must not receive this one.
        await transport.broadcastResourceUpdated(uri: URL(string: uri)!)

        // Past one retention interval the janitor reclaims the stream and the
        // primary slot falls back to the live, bound stream; the next broadcast
        // must arrive. (The reclaim runs inside the broadcast's own cleanup.)
        try await Task.sleep(nanoseconds: 1_500_000_000)
        await transport.broadcastResourceUpdated(uri: URL(string: uri)!)

        #expect(await manager.primaryGeneralStreamID(for: sessionUUID) == liveStreamID)
        let received = await HTTPTransportTestHelpers.waitForCondition {
            HTTPTransportTestHelpers.notificationEvent(
                capture.events.value, method: "notifications/resources/updated"
            ) != nil
        }
        #expect(received, "broadcast did not arrive after the abandoned stream was reclaimed")

        capture.task.cancel()
    }

    // MARK: - Helpers

    private func initializeAndSubscribe(
        uri: String,
        mcpURL: URL,
        urlSession: URLSession
    ) async throws -> (sessionID: String, sessionUUID: UUID) {
        let (sessionID, _) = try await HTTPTransportTestHelpers.initializeSession(
            url: mcpURL, urlSession: urlSession
        )

        let subscribe = JSONRPCMessage.request(
            id: 100,
            method: "resources/subscribe",
            params: ["uri": .string(uri)]
        )
        let request = try HTTPTransportTestHelpers.streamablePOSTRequest(
            url: mcpURL, message: subscribe, sessionID: sessionID
        )
        let (response, events) = try await HTTPTransportTestHelpers.readFiniteSSEResponse(
            request, urlSession: urlSession
        )
        #expect(response.statusCode == 200)
        #expect(HTTPTransportTestHelpers.responseEvent(events, id: 100) != nil)

        return (sessionID, try #require(UUID(uuidString: sessionID)))
    }

    private func openLiveGeneralStream(
        sessionID: String,
        mcpURL: URL,
        urlSession: URLSession
    ) async throws -> HTTPTransportStreamCapture {
        let streamRequest = HTTPTransportTestHelpers.generalSSERequest(url: mcpURL, sessionID: sessionID)
        let capture = HTTPTransportTestHelpers.openStreamingRequest(streamRequest, urlSession: urlSession)
        let live = await HTTPTransportTestHelpers.waitForCondition {
            capture.response.value?.statusCode == 200 && !capture.events.value.isEmpty
        }
        #expect(live, "general stream never became live")
        return capture
    }
}
#endif
