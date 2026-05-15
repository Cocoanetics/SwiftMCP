// Test-only: HTTP responses are known to be HTTPURLResponse.

import Testing
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import SwiftMCP

@Suite("HTTP Transport Stream Resume and Routing")
struct HTTPTransportResumeTests {

    @Test("GET /mcp: general stream primes and can resume missed notifications")
    func generalStreamResume() async throws {
        #if canImport(FoundationNetworking)
        return
        #else
        let (transport, baseURL) = try await HTTPTransportTestHelpers.startTransport()
        defer { Task { try? await transport.stop() } }

        let url = baseURL.appendingPathComponent("mcp")
        let (sessionID, _) = try await HTTPTransportTestHelpers.initializeSession(url: url)
        let capture = HTTPTransportTestHelpers.openStreamingRequest(
            HTTPTransportTestHelpers.generalSSERequest(url: url, sessionID: sessionID)
        )

        let primed = await HTTPTransportTestHelpers.waitForCondition {
            capture.response.value != nil && !capture.events.value.isEmpty
        }
        #expect(primed)

        let primingEvent = try #require(capture.events.value.first)
        let primingEventID = try #require(primingEvent.id)
        capture.task.cancel()

        try? await Task.sleep(nanoseconds: 100_000_000)
        await transport.broadcastToolsListChanged()
        try? await Task.sleep(nanoseconds: 50_000_000)

        let resumed = HTTPTransportTestHelpers.openStreamingRequest(
            HTTPTransportTestHelpers.generalSSERequest(url: url, sessionID: sessionID, lastEventID: primingEventID)
        )
        let resumedReceived = await HTTPTransportTestHelpers.waitForCondition {
            HTTPTransportTestHelpers.notificationEvent(
                resumed.events.value, method: "notifications/tools/list_changed"
            ) != nil
        }
        #expect(resumedReceived)

        let notification = try #require(HTTPTransportTestHelpers.notificationEvent(
            resumed.events.value, method: "notifications/tools/list_changed"
        ))
        #expect(notification.id != nil)
        resumed.task.cancel()
        #endif
    }

    @Test("POST /mcp: request stream can resume after disconnect")
    func requestStreamResume() async throws {
        #if canImport(FoundationNetworking)
        return
        #else
        let (transport, baseURL) = try await HTTPTransportTestHelpers.startTransport(server: ResumableServer())
        defer { Task { try? await transport.stop() } }

        let url = baseURL.appendingPathComponent("mcp")
        let (sessionID, _) = try await HTTPTransportTestHelpers.initializeSession(url: url)

        let requestCapture = HTTPTransportTestHelpers.openStreamingRequest(
            try HTTPTransportTestHelpers.streamablePOSTRequest(
                url: url,
                message: .request(
                    id: 2,
                    method: "tools/call",
                    params: [
                        "name": .string("slowPing"),
                        "arguments": .object([:]),
                        "_meta": .object([
                            "progressToken": .string("slow-request")
                        ])
                    ]
                ),
                sessionID: sessionID
            )
        )

        let sawProgress = await HTTPTransportTestHelpers.waitForCondition {
            HTTPTransportTestHelpers.notificationEvent(
                requestCapture.events.value, method: "notifications/progress"
            ) != nil
        }
        #expect(sawProgress)

        let lastSeenEventID = try #require(requestCapture.events.value.last?.id)
        requestCapture.task.cancel()

        try? await Task.sleep(nanoseconds: 500_000_000)

        let resumedRequest = try await HTTPTransportTestHelpers.readFiniteSSEResponse(
            HTTPTransportTestHelpers.generalSSERequest(url: url, sessionID: sessionID, lastEventID: lastSeenEventID)
        )

        #expect(HTTPTransportTestHelpers.notificationEvent(resumedRequest.1, method: "notifications/progress") != nil)
        #expect(HTTPTransportTestHelpers.responseEvent(resumedRequest.1, id: 2) != nil)
        #endif
    }

    @Test("Multiple general streams route unsolicited notifications only to the newest active stream")
    func multipleGeneralStreamsPrimarySelection() async throws {
        #if canImport(FoundationNetworking)
        return
        #else
        let (transport, baseURL) = try await HTTPTransportTestHelpers.startTransport()
        defer { Task { try? await transport.stop() } }

        let url = baseURL.appendingPathComponent("mcp")
        let (sessionID, _) = try await HTTPTransportTestHelpers.initializeSession(url: url)

        let streamA = HTTPTransportTestHelpers.openStreamingRequest(
            HTTPTransportTestHelpers.generalSSERequest(url: url, sessionID: sessionID)
        )
        let streamAReady = await HTTPTransportTestHelpers.waitForCondition {
            !streamA.events.value.isEmpty
        }
        #expect(streamAReady)

        let streamB = HTTPTransportTestHelpers.openStreamingRequest(
            HTTPTransportTestHelpers.generalSSERequest(url: url, sessionID: sessionID)
        )
        let streamBReady = await HTTPTransportTestHelpers.waitForCondition {
            !streamB.events.value.isEmpty
        }
        #expect(streamBReady)

        await transport.broadcastPromptsListChanged()
        let received = await HTTPTransportTestHelpers.waitForCondition {
            HTTPTransportTestHelpers.notificationEvent(
                streamB.events.value, method: "notifications/prompts/list_changed"
            ) != nil
        }
        #expect(received)
        #expect(HTTPTransportTestHelpers.notificationEvent(
            streamA.events.value, method: "notifications/prompts/list_changed"
        ) == nil)

        streamA.task.cancel()
        streamB.task.cancel()
        #endif
    }
}
