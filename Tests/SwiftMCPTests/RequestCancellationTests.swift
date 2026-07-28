//
//  RequestCancellationTests.swift
//  SwiftMCP
//
//  `notifications/cancelled` used to be an explicit no-op: a long-running tool
//  kept working for a client that had already given up on the request (#171
//  §4a). These tests drive the dispatch layer directly — the transport-level
//  path (a disconnect cancelling in-flight work) is covered by
//  `TCPTransportTeardownTests`.
//

import Testing
import Foundation
@testable import SwiftMCP

/// Observes a hanging tool from the outside: when its body started running,
/// and whether it exited through the cancellation path.
actor ToolRunObserver {
    private(set) var started = false
    private(set) var cancelled = false

    func markStarted() { started = true }
    func markCancelled() { cancelled = true }

    func waitUntilStarted(timeout: TimeInterval = 5) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !started, Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return started
    }

    func waitUntilCancelled(timeout: TimeInterval = 5) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !cancelled, Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return cancelled
    }
}

/// A server whose only tool runs until its task is cancelled — the shape of a
/// streaming/watching tool body (`while !Task.isCancelled`).
@MCPServer(name: "Hanger")
final class HangingServer: @unchecked Sendable {
    let observer = ToolRunObserver()

    /// Runs until the surrounding task is cancelled.
    @MCPTool(description: "Runs until cancelled")
    func hang() async -> String {
        await observer.markStarted()
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        await observer.markCancelled()
        return "cancelled"
    }

    /// Takes a moment, then answers — long enough for a client to half-close
    /// while it is still computing.
    @MCPTool(description: "Answers after a short delay")
    func slow() async -> String {
        await observer.markStarted()
        try? await Task.sleep(nanoseconds: 400_000_000)
        return "slow-done"
    }
}

@Suite("Request cancellation")
struct RequestCancellationTests {

    @Test("notifications/cancelled cancels the in-flight request and suppresses its response")
    func cancelledNotificationCancelsInFlightRequest() async throws {
        let server = HangingServer()
        let session = Session(id: UUID())

        let request = JSONRPCMessage.request(
            id: .integer(42),
            method: "tools/call",
            params: .object([
                "name": .string("hang"),
                "arguments": .object([:])
            ])
        )

        let processing = Task {
            await session.work { _ in await server.handleMessage(request) }
        }

        #expect(await server.observer.waitUntilStarted())

        let cancelNotification = JSONRPCMessage.notification(
            method: "notifications/cancelled",
            params: .object(["requestId": .integer(42)])
        )
        _ = await session.work { _ in await server.handleMessage(cancelNotification) }

        // Bounded: if cancellation never reaches the tool, fail instead of hanging.
        let watchdog = Task {
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            processing.cancel()
        }
        defer { watchdog.cancel() }

        let response = await processing.value
        #expect(await server.observer.cancelled)
        // The client stopped listening for this response; it must be suppressed.
        #expect(response == nil)
    }

    @Test("A cancellation that overtakes its request still cancels it")
    func preemptiveCancellation() async throws {
        let server = HangingServer()
        let session = Session(id: UUID())

        // Dispatch tasks are unordered, so a cancellation can reach the
        // session before its request registers. It must be retained and fire
        // the moment the request shows up — not dropped as unknown.
        let cancelNotification = JSONRPCMessage.notification(
            method: "notifications/cancelled",
            params: .object(["requestId": .integer(9)])
        )
        _ = await session.work { _ in await server.handleMessage(cancelNotification) }

        let request = JSONRPCMessage.request(
            id: .integer(9),
            method: "tools/call",
            params: .object([
                "name": .string("hang"),
                "arguments": .object([:])
            ])
        )
        let response = await session.work { _ in await server.handleMessage(request) }

        #expect(response == nil)
        #expect(await server.observer.cancelled)
    }

    @Test("A cancellation for an unknown request id is a no-op")
    func unknownRequestIDIsNoOp() async throws {
        let server = HangingServer()
        let session = Session(id: UUID())

        let cancelNotification = JSONRPCMessage.notification(
            method: "notifications/cancelled",
            params: .object(["requestId": .integer(7)])
        )
        let reply = await session.work { _ in await server.handleMessage(cancelNotification) }
        #expect(reply == nil)
    }

    @Test("An uncancelled request still gets its response")
    func uncancelledRequestResponds() async throws {
        let server = StructCalculator()
        let session = Session(id: UUID())

        let request = JSONRPCMessage.request(
            id: .integer(1),
            method: "tools/call",
            params: .object([
                "name": .string("add"),
                "arguments": .object(["a": .integer(2), "b": .integer(3)])
            ])
        )

        let response = await session.work { _ in await server.handleMessage(request) }
        #expect(response != nil)
        #expect(response?.id == .integer(1))
    }

    @Test("A string request id cancels too")
    func stringRequestID() async throws {
        let server = HangingServer()
        let session = Session(id: UUID())

        let request = JSONRPCMessage.request(
            id: .string("req-1"),
            method: "tools/call",
            params: .object([
                "name": .string("hang"),
                "arguments": .object([:])
            ])
        )

        let processing = Task {
            await session.work { _ in await server.handleMessage(request) }
        }

        #expect(await server.observer.waitUntilStarted())

        let cancelNotification = JSONRPCMessage.notification(
            method: "notifications/cancelled",
            params: .object(["requestId": .string("req-1")])
        )
        _ = await session.work { _ in await server.handleMessage(cancelNotification) }

        let watchdog = Task {
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            processing.cancel()
        }
        defer { watchdog.cancel() }

        let response = await processing.value
        #expect(await server.observer.cancelled)
        #expect(response == nil)
    }
}
