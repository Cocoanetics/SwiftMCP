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
import Logging
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
/// EventLoop that has already shut down". `quiesce(slowHandlerWarningAfter:)`
/// closes every channel and awaits its handler tasks while the loops are still
/// up, so no touch is left to land on a closed one.
///
/// Lock-protected rather than an actor: registration runs on an event loop,
/// inside the synchronous child-channel initializer.
final class NIOConnectionRegistry: @unchecked Sendable {
    private let logger: Logger
    private let lock = NIOLock()
    private var channels: [ObjectIdentifier: Channel] = [:]
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var isQuiescing = false

    init(logger: Logger) {
        self.logger = logger
    }

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
    /// for every one of them to finish.
    ///
    /// Cancellation is what ends an SSE handler: its drain loop is parked on
    /// the stream's next event, and the engine does not finish a stream whose
    /// connection dropped — it retains it for a resume. Whatever a cancelled
    /// task still writes fails on the closed channel, whose loop is still up.
    ///
    /// The wait has no deadline. A task released early would still be able to
    /// touch its channel once it resumes — attach to its close future, write
    /// its stream's end — and that is exactly the scheduling onto a shut-down
    /// loop this registry exists to prevent; the loops stay up until the last
    /// task is done. A handler that ignores cancellation therefore holds the
    /// shutdown for as long as it runs, which is logged after
    /// `slowHandlerWarningAfter` so a hung stop can be traced to it.
    func quiesce(slowHandlerWarningAfter warningDelay: TimeInterval) async {
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
        let watchdog = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(warningDelay * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            let remaining = lock.withLock { self.tasks.count }
            if remaining > 0 {
                let message = "Shutdown is waiting for \(remaining) request handler(s) still running "
                    + "\(warningDelay)s after cancellation; the event loops stay up until they finish"
                logger.warning("\(message)")
            }
        }
        for task in tasks {
            await task.value
        }
        watchdog.cancel()
    }
}
#endif
