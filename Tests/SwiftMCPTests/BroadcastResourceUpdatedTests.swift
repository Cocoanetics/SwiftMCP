#if Server
// Reproduces the MissionControl "zombie session" defect: a client that connects
// immediately at server start, subscribes, and holds a general GET stream must
// receive `notifications/resources/updated` broadcasts. See the production
// incident of 2026-08-12 (session healthy for POSTs and keepalives, but no
// pushes for 10+ hours).

import Foundation
import Testing
import SwiftCross
@testable import SwiftMCP

@MCPServer(name: "PushFixtureServer")
final class PushFixtureServer {
    /// A subscribable resource, so `exposesResources` is true and
    /// `resources/subscribe` is accepted.
    @MCPResource("push://status")
    func status() -> String {
        return "ok"
    }
}

@Suite("Broadcast resource-updated delivery", .serialized)
struct BroadcastResourceUpdatedTests {

    static let subscribedURIs: [String] = (0..<10).map { "push://resource/\($0)" }

    /// Mirrors the production client: initialize, then fire the general GET
    /// stream and the subscribe POSTs concurrently, then broadcast and assert
    /// the notification arrives on the general stream.
    @Test func clientConnectingAtBootReceivesBroadcasts() async throws {
        for iteration in 0..<3 {
            let (transport, baseURL) = try await HTTPTransportTestHelpers.startTransport(
                server: PushFixtureServer()
            )

            do {
                try await runBootWindowScenario(
                    transport: transport,
                    baseURL: baseURL,
                    iteration: iteration
                )
            } catch {
                try? await transport.stop()
                throw error
            }

            try await transport.stop()
        }
    }

    private func runBootWindowScenario(
        transport: HTTPSSETransport,
        baseURL: URL,
        iteration: Int
    ) async throws {
        let mcpURL = baseURL.appendingPathComponent("mcp")
        let urlSession = URLSession(configuration: .ephemeral)

        // 1. initialize — the first request the server ever sees.
        let (sessionID, initEvents) = try await HTTPTransportTestHelpers.initializeSession(
            url: mcpURL, urlSession: urlSession
        )
        #expect(HTTPTransportTestHelpers.responseEvent(initEvents, id: 1) != nil)

        // 2. General GET stream and the 10 subscribe POSTs race, as the real
        //    client does (connect() starts the GET task and returns; the app
        //    then subscribes immediately).
        let streamRequest = HTTPTransportTestHelpers.generalSSERequest(
            url: mcpURL, sessionID: sessionID
        )
        let capture = HTTPTransportTestHelpers.openStreamingRequest(
            streamRequest, urlSession: urlSession
        )

        try await subscribeAll(mcpURL: mcpURL, sessionID: sessionID, urlSession: urlSession, iteration: iteration)

        // 3. The general stream must be up before broadcasting: wait for its
        //    priming event (a data event carrying the resume anchor).
        let streamLive = await HTTPTransportTestHelpers.waitForCondition {
            capture.response.value?.statusCode == 200 && !capture.events.value.isEmpty
        }
        #expect(streamLive, "general stream never became live (iteration \(iteration))")

        // 4. Broadcast to one of the subscribed URIs.
        let updatedURI = URL(string: Self.subscribedURIs[iteration % Self.subscribedURIs.count])!
        await transport.broadcastResourceUpdated(uri: updatedURI)

        // 5. The push must arrive on the general stream.
        let received = await HTTPTransportTestHelpers.waitForCondition(timeoutNanoseconds: 10_000_000_000) {
            HTTPTransportTestHelpers.notificationEvent(
                capture.events.value, method: "notifications/resources/updated"
            ) != nil
        }

        if !received {
            let diagnostics = await Self.dumpRoutingState(transport: transport, sessionID: sessionID)
            Issue.record(
                "notifications/resources/updated never arrived (iteration \(iteration)); \(diagnostics)"
            )
        }

        capture.task.cancel()
        urlSession.invalidateAndCancel()
    }

    /// Subscribe to every URI concurrently, as the real client's requests race
    /// the general GET during connect.
    private func subscribeAll(
        mcpURL: URL,
        sessionID: String,
        urlSession: URLSession,
        iteration: Int
    ) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for (index, uri) in Self.subscribedURIs.enumerated() {
                group.addTask {
                    let subscribe = JSONRPCMessage.request(
                        id: 100 + index,
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
                    guard HTTPTransportTestHelpers.responseEvent(events, id: 100 + index) != nil else {
                        throw TestError("subscribe \(uri) did not return a result (iteration \(iteration))")
                    }
                }
            }
            try await group.waitForAll()
        }
    }

    /// Snapshot the session-manager routing state for a failed iteration.
    static func dumpRoutingState(transport: HTTPSSETransport, sessionID: String) async -> String {
        guard let sessionUUID = UUID(uuidString: sessionID) else {
            return "malformed session id"
        }
        let manager = transport.sessionManager
        let hasSession = await manager.hasSession(id: sessionUUID)
        let primary = await manager.primaryGeneralStreamID(for: sessionUUID)
        let active = await manager.hasActivePrimaryGeneralConnection(for: sessionUUID)
        var subscribed: Set<String> = []
        if let session = await manager.existingSession(id: sessionUUID) {
            for uri in subscribedURIs {
                guard await session.isSubscribedToResource(uri: uri) else { continue }
                subscribed.insert(uri)
            }
        }
        return "hasSession=\(hasSession) primaryStream=\(String(describing: primary)) "
            + "primaryActive=\(active) subscriptionsRecorded=\(subscribed.count)/\(subscribedURIs.count)"
    }
}
#endif
