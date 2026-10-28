//
//  NIOConnectionRegistry.swift
//  SwiftMCP
//
//  The accepted-connection and handler-task bookkeeping behind
//  `NIOHTTPServerAdapter.shutdown()`; with `NIOHTTPServerAdapter.swift`,
//  `NIOHTTPChannelHandler.swift` and `NIOSSEConnection.swift` the only
//  server-side code linking swift-nio.
//

#if Server
import Foundation
@preconcurrency import NIOConcurrencyHelpers
@preconcurrency import NIOCore

/// The connections the listener accepted and the handler tasks serving them,
/// so the adapter's shutdown can quiesce both before its event loops go down.
///
/// Closing the listener first (#217) keeps *new* connections off a dying loop.
/// The *accepted* ones still touch their loop from off it for as long as they
/// live — an SSE write awaited from a handler task, the post-response check,
/// an engine-side `terminate()` — and each such touch after
/// `shutdownGracefully` closed the loop is NIO's "Cannot schedule tasks on an
/// EventLoop that has already shut down". `quiesce(timeout:)` closes every
/// channel and awaits its handler tasks while the loops are still up, so no
/// touch is left to land on a closed one.
///
/// Lock-protected rather than an actor: registration runs on an event loop,
/// inside the synchronous child-channel initializer.
final class NIOConnectionRegistry: @unchecked Sendable {
    private let lock = NIOLock()
    private var channels: [ObjectIdentifier: Channel] = [:]
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var isQuiescing = false

    /// Track `channel` until it closes. `false` once the quiesce has begun:
    /// the caller closes the channel instead of serving it.
    func register(_ channel: Channel) -> Bool {
        let id = ObjectIdentifier(channel)
        let accepted = lock.withLock { () -> Bool in
            guard !isQuiescing else { return false }
            channels[id] = channel
            return true
        }
        guard accepted else { return false }
        channel.closeFuture.whenComplete { [weak self] _ in
            guard let self else { return }
            lock.withLock { _ = channels.removeValue(forKey: id) }
        }
        return true
    }

    /// Run `operation` as a tracked handler task. Refused once the quiesce has
    /// begun: the connection is closing, there is nobody left to reply to.
    func spawn(_ operation: @escaping @Sendable () async -> Void) {
        lock.withLock {
            guard !isQuiescing else { return }
            let id = UUID()
            // Created while holding the lock so the task is registered before
            // its self-removal can run.
            tasks[id] = Task { [weak self] in
                await operation()
                guard let self else { return }
                lock.withLock { _ = tasks.removeValue(forKey: id) }
            }
        }
    }

    /// Close every tracked connection, then cancel its handler tasks and wait
    /// for them — until `timeout` passes, so a handler that ignores
    /// cancellation cannot hold the shutdown forever.
    ///
    /// Cancellation is what ends an SSE handler: its drain loop is parked on
    /// the stream's next event, and the engine does not finish a stream whose
    /// connection dropped — it retains it for a resume. Whatever a cancelled
    /// task still writes fails on the closed channel, whose loop is still up.
    func quiesce(timeout: TimeInterval) async {
        let (channels, tasks) = lock.withLock { () -> ([Channel], [Task<Void, Never>]) in
            isQuiescing = true
            return (Array(self.channels.values), Array(self.tasks.values))
        }
        for channel in channels {
            channel.close(promise: nil)
        }
        for channel in channels {
            try? await channel.closeFuture.get()
        }
        for task in tasks {
            task.cancel()
        }
        let deadline = Date().addingTimeInterval(timeout)
        while !isDrained, Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private var isDrained: Bool {
        lock.withLock { tasks.isEmpty }
    }
}
#endif
