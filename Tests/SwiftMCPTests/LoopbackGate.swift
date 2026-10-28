//
//  LoopbackGate.swift
//  SwiftMCP
//
//  Keeps the HTTP lifecycle churn tests from overlapping loopback suites (#220).
//

#if Server
import Testing
import Foundation
@testable import SwiftMCP

/// Lets the churn tests in `HTTPTransportLifecycleTests` run alone. `.serialized` only orders tests within
/// one suite, so on the 2-core Android emulator the churn overlapped the
/// loopback suites that time-box a stream or a request, starving them (#220).
/// Churn tests take the gate exclusively; suites that are sensitive to that load
/// opt in as shared holders with `.loopbackShared`.
actor LoopbackGate {
    static let shared = LoopbackGate()

    private var holders = 0
    private var exclusiveHeld = false
    private var waiters: [(exclusive: Bool, continuation: CheckedContinuation<Void, Never>)] = []

    private var exclusiveWaiting: Bool { waiters.contains { $0.exclusive } }

    func acquire(exclusive: Bool) async {
        let free = exclusive ? (holders == 0 && !exclusiveHeld) : (!exclusiveHeld && !exclusiveWaiting)
        if free && waiters.isEmpty {
            take(exclusive: exclusive)
            return
        }
        await withCheckedContinuation { waiters.append((exclusive, $0)) }
    }

    func release(exclusive: Bool) {
        if exclusive { exclusiveHeld = false } else { holders -= 1 }
        while let next = waiters.first {
            if next.exclusive {
                guard holders == 0 else { return }
            } else if exclusiveHeld {
                return
            }
            waiters.removeFirst()
            take(exclusive: next.exclusive)
            next.continuation.resume()
        }
    }

    private func take(exclusive: Bool) {
        if exclusive { exclusiveHeld = true } else { holders += 1 }
    }

    /// Number of acquires currently suspended, waiting for the gate.
    var waiterCount: Int { waiters.count }

    /// Number of shared holders and whether the gate is held exclusively.
    var state: (shared: Int, exclusive: Bool) { (holders, exclusiveHeld) }
}

/// Teardown that a test can only schedule (from a `defer`), not await. Gated
/// tests start it with `run`; the gate trait awaits it before releasing, so an
/// exclusive test never starts while a shared test's servers are still closing.
enum LoopbackTeardown {
    private static let pending = HTTPTransportBox<[Task<Void, Never>]>([])

    static func run(_ body: @escaping @Sendable () async -> Void) {
        let task = Task { await body() }
        pending.modify { $0.append(task) }
    }

    static func drain() async {
        while true {
            var next: Task<Void, Never>?
            pending.modify { next = $0.isEmpty ? nil : $0.removeFirst() }
            guard let task = next else { return }
            await task.value
        }
    }
}

struct LoopbackGateTrait: TestTrait, SuiteTrait, TestScoping {
    let exclusive: Bool
    var isRecursive: Bool { true }

    func provideScope(for test: Test, testCase: Test.Case?,
                      performing function: @Sendable () async throws -> Void) async throws {
        // Suites recurse into their tests; only test functions take the gate.
        guard !test.isSuite else { return try await function() }
        await LoopbackGate.shared.acquire(exclusive: exclusive)
        do {
            try await function()
        } catch {
            await LoopbackTeardown.drain()
            await LoopbackGate.shared.release(exclusive: exclusive)
            throw error
        }
        await LoopbackTeardown.drain()
        await LoopbackGate.shared.release(exclusive: exclusive)
    }
}

extension Trait where Self == LoopbackGateTrait {
    /// Runs the test with no other gated test running.
    static var loopbackExclusive: Self { Self(exclusive: true) }
    /// Runs the test alongside other shared tests, but never during an exclusive one.
    static var loopbackShared: Self { Self(exclusive: false) }
}
#endif
