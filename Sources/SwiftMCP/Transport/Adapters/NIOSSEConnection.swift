//
//  NIOSSEConnection.swift
//  SwiftMCP
//
//  The ``SSEConnection`` implementations the NIO adapter binds engine streams
//  to; with `NIOHTTPServerAdapter.swift`, `NIOHTTPChannelHandler.swift` and
//  `NIOConnectionRegistry.swift` the only server-side code linking swift-nio.
//

#if Server
@preconcurrency import NIOCore

/// An ``SSEConnection`` backed by a live NIO `Channel`.
final class NIOSSEConnection: SSEConnection {
    private let channel: Channel
    init(channel: Channel) { self.channel = channel }
    var isConnected: Bool { channel.isActive }
    /// Closing schedules onto the channel's loop, and the engine may terminate
    /// a stream's connection (expiry, a stale registration) after the adapter
    /// has shut that loop down. The adapter closes every channel before its
    /// loops, and a closed channel never turns active again, so an inactive
    /// one needs — and gets — no close.
    func terminate() {
        guard channel.isActive else { return }
        channel.close(promise: nil)
    }
}

/// A never-connected ``SSEConnection``, used to reconcile SSE streams whose
/// response was discarded before any connection could bind.
final class DeadSSEConnection: SSEConnection {
    init() {}
    var isConnected: Bool { false }
    func terminate() {}
}
#endif
