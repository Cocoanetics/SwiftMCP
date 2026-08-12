#if Server
// Reproduces the MissionControl zombie with SwiftMCP's own client: the real
// MCPServerProxy abandons each POST's SSE stream as soon as its response event
// arrives, which raw-URLSession tests don't replicate. Mirrors the Mac app's
// maintain() loop: connect (initialize + notifications/initialized + general
// GET task), sequential subscribes, then rely on pushes — while broadcast
// churn and agent-like POST traffic hammer the same server, as the production
// daemon does from the moment it boots.

import Foundation
import Testing
import SwiftCross
@testable import SwiftMCP

/// Records resource-updated notifications delivered to the proxy.
final class PushRecorder: MCPServerProxyResourceNotificationHandling, @unchecked Sendable {
    private let received = HTTPTransportBox<[URL]>([])

    func mcpServerProxy(_ proxy: MCPServerProxy, resourceUpdatedAt uri: URL) async {
        received.modify { $0.append(uri) }
    }

    var count: Int {
        received.value.count
    }
}

@Suite("Broadcast delivery to real proxy", .serialized)
struct BroadcastRealProxyTests {

    static let subscribedURIs: [String] = (0..<10).map { "push://resource/\($0)" }

    @Test(.timeLimit(.minutes(10)))
    func proxyConnectingAtBootReceivesBroadcasts() async throws {
        for iteration in 0..<4 {
            let (transport, baseURL) = try await HTTPTransportTestHelpers.startTransport(
                server: PushFixtureServer()
            )
            try await runIteration(transport: transport, baseURL: baseURL, iteration: iteration)
        }
    }

    private func runIteration(transport: HTTPSSETransport, baseURL: URL, iteration: Int) async throws {
        let mcpURL = baseURL.appendingPathComponent("mcp")

        // Broadcast churn from the instant the server is up, like the daemon's
        // monitor sweeps and log rebroadcasts.
        let broadcasting = Task {
            var round = 0
            while !Task.isCancelled {
                let uri = URL(string: Self.subscribedURIs[round % Self.subscribedURIs.count])!
                await transport.broadcastResourceUpdated(uri: uri)
                await transport.broadcastLog(LogMessage(level: .info, data: ["round": .integer(round)]))
                round += 1
                try? await Task.sleep(nanoseconds: 2_000_000)
            }
        }

        // Agent-like background POST traffic on its own session, as the daemon
        // sees from CLI/agent clients while the app connects.
        let agentSession = URLSession(configuration: .ephemeral)
        let agentTraffic = try await startAgentTraffic(mcpURL: mcpURL, urlSession: agentSession)

        let recorder = PushRecorder()
        let proxy = MCPServerProxy(config: .sse(config: MCPServerSseConfig(url: mcpURL)))
        await proxy.setResourceNotificationHandler(recorder)

        // Quiesce all background work before stopping the transport, so no send
        // races the adapter shutdown, then release CFNetwork's descriptors.
        func quiesce() async {
            broadcasting.cancel()
            agentTraffic.cancel()
            _ = await broadcasting.result
            _ = await agentTraffic.result
            await proxy.disconnect()
            agentSession.invalidateAndCancel()
        }

        do {
            try await connectAndAssertPushArrives(
                proxy: proxy, recorder: recorder, transport: transport, iteration: iteration
            )
        } catch {
            await quiesce()
            try? await transport.stop()
            throw error
        }

        await quiesce()
        try await transport.stop()
    }

    /// Ping the server in a tight loop from a separate session until cancelled.
    private func startAgentTraffic(mcpURL: URL, urlSession: URLSession) async throws -> Task<Void, Never> {
        let (sessionID, _) = try await HTTPTransportTestHelpers.initializeSession(
            url: mcpURL, urlSession: urlSession
        )
        return Task {
            var requestID = 1000
            while !Task.isCancelled {
                let ping = JSONRPCMessage.request(id: requestID, method: "ping")
                if let request = try? HTTPTransportTestHelpers.streamablePOSTRequest(
                    url: mcpURL, message: ping, sessionID: sessionID
                ) {
                    _ = try? await HTTPTransportTestHelpers.readFiniteSSEResponse(
                        request, urlSession: urlSession
                    )
                }
                requestID += 1
            }
        }
    }

    private func connectAndAssertPushArrives(
        proxy: MCPServerProxy,
        recorder: PushRecorder,
        transport: HTTPSSETransport,
        iteration: Int
    ) async throws {
        try await proxy.connect(clientName: "MissionControl", clientVersion: "0.1.0")
        for uri in Self.subscribedURIs {
            try await proxy.subscribeResource(uri: URL(string: uri)!)
        }

        // The broadcaster fires every 2ms; a healthy session sees a push
        // near-instantly. 10s is a failure bound, not a wait.
        let received = await HTTPTransportTestHelpers.waitForCondition(
            timeoutNanoseconds: 10_000_000_000
        ) {
            recorder.count > 0
        }

        guard !received else { return }

        let sessionID = await proxy.sessionID ?? "nil"
        let diagnostics = await BroadcastResourceUpdatedTests.dumpRoutingState(
            transport: transport, sessionID: sessionID
        )
        Issue.record("ZOMBIE reproduced at iteration \(iteration): \(diagnostics)")
    }
}
#endif
