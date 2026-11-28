#if Client
// Helpers for the proxy HTTP session lifecycle tests (#277).

import SwiftMCP

/// Holds requests at ``MCPProxyHTTPSession``'s start gate until released, and
/// reports when one has arrived there.
actor StartGate {
    private var hasArrived = false
    private var isReleased = false
    private var arrivalWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func pass() async {
        hasArrived = true
        for waiter in arrivalWaiters {
            waiter.resume()
        }
        arrivalWaiters.removeAll()
        guard !isReleased else { return }
        await withCheckedContinuation { releaseWaiters.append($0) }
    }

    func waitForArrival() async {
        guard !hasArrived else { return }
        await withCheckedContinuation { arrivalWaiters.append($0) }
    }

    func release() {
        isReleased = true
        for waiter in releaseWaiters {
            waiter.resume()
        }
        releaseWaiters.removeAll()
    }
}

#if Server
/// A server whose tool stays in flight until released.
@MCPServer(name: "HeldToolServer", version: "1.0.0")
actor HeldToolServer {
    private var waiters: [CheckedContinuation<String, Never>] = []

    var pendingCount: Int {
        waiters.count
    }

    /// Suspends until the test releases it.
    @MCPTool
    func waitForRelease() async -> String {
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        for waiter in waiters {
            waiter.resume(returning: "released")
        }
        waiters.removeAll()
    }
}
#endif
#endif
