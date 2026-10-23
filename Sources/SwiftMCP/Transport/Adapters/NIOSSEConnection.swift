//
//  NIOSSEConnection.swift
//  SwiftMCP
//
//  The ``SSEConnection`` implementations the NIO adapter binds engine streams
//  to; with `NIOHTTPServerAdapter.swift` the only server-side code linking
//  swift-nio.
//

#if Server
@preconcurrency import NIOCore

/// An ``SSEConnection`` backed by a live NIO `Channel`.
final class NIOSSEConnection: SSEConnection {
    private let channel: Channel
    init(channel: Channel) { self.channel = channel }
    var isConnected: Bool { channel.isActive }
    func terminate() { channel.close(promise: nil) }
}

/// A never-connected ``SSEConnection``, used to reconcile SSE streams whose
/// response was discarded before any connection could bind.
final class DeadSSEConnection: SSEConnection {
    init() {}
    var isConnected: Bool { false }
    func terminate() {}
}
#endif
