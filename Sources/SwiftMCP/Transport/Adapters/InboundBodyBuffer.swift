#if Server
import Foundation
import NIOConcurrencyHelpers

/// Hands inbound HTTP body chunks from the event loop to a Swift-concurrency
/// consumer with bounded buffering.
///
/// The channel handler ``append(_:)``s chunks synchronously on the event
/// loop; the route handler consumes ``stream``. When buffered bytes exceed
/// ``highWatermark`` the buffer pauses channel reads, and resumes them once
/// the consumer drains below ``lowWatermark`` — TCP flow control then pushes
/// back on the sender instead of the whole request body queueing in memory.
///
/// ``finish()`` ends the stream after the final chunk. ``abort()`` ends it
/// immediately and discards anything buffered — used when the connection
/// dies, so a consumer can never park forever on a dead upload.
final class InboundBodyBuffer: @unchecked Sendable {
    /// Pause channel reads once this many bytes are buffered.
    static let highWatermark = 1 << 20
    /// Resume channel reads once the buffer drains below this many bytes.
    static let lowWatermark = 256 << 10

    private struct State {
        var chunks: [Data] = []
        var bufferedBytes = 0
        var finished = false
        var aborted = false
        var readsPaused = false
        var waiter: CheckedContinuation<Data?, Never>?
    }

    private let lock = NIOLock()
    private var state = State()
    private let pauseReads: @Sendable () -> Void
    private let resumeReads: @Sendable () -> Void

    /// Creates a buffer with injectable read control.
    ///
    /// - Parameters:
    ///   - pauseReads: Invoked (off-lock) when the high watermark is crossed.
    ///   - resumeReads: Invoked (off-lock) when the buffer drains below the
    ///     low watermark after having been paused.
    init(
        pauseReads: @escaping @Sendable () -> Void,
        resumeReads: @escaping @Sendable () -> Void
    ) {
        self.pauseReads = pauseReads
        self.resumeReads = resumeReads
    }

    /// The consumer-facing stream. Single consumer.
    var stream: AsyncStream<Data> {
        AsyncStream(unfolding: { await self.next() })
    }

    /// Bytes currently buffered (for tests and diagnostics).
    var bufferedByteCount: Int {
        lock.withLock { state.bufferedBytes }
    }

    /// Whether the body was aborted (oversize rejection, dead connection).
    ///
    /// When `true`, the channel-read layer owns the connection's fate — it
    /// has already answered (413) or the peer is gone. The dispatched route
    /// handler must not write a response of its own: a second response for
    /// the same request trips NIO's HTTP pipeline handler `fatalError`
    /// ("Unexpectedly received a response in state idle") and kills the
    /// process.
    var wasAborted: Bool {
        lock.withLock { state.aborted }
    }

    // MARK: - Producer side (event loop)

    /// Enqueues a chunk, handing it straight to a parked consumer when one
    /// is waiting.
    func append(_ data: Data) {
        var waiterToResume: CheckedContinuation<Data?, Never>?
        var crossedHighWatermark = false
        lock.withLock {
            guard !state.finished else { return }
            if let waiter = state.waiter {
                state.waiter = nil
                waiterToResume = waiter
            } else {
                state.chunks.append(data)
                state.bufferedBytes += data.count
                if !state.readsPaused, state.bufferedBytes > Self.highWatermark {
                    state.readsPaused = true
                    crossedHighWatermark = true
                }
            }
        }
        waiterToResume?.resume(returning: data)
        if crossedHighWatermark {
            pauseReads()
        }
    }

    /// Ends the stream after everything already buffered has been consumed.
    func finish() {
        end(discardBuffered: false)
    }

    /// Ends the stream immediately, discarding buffered chunks.
    func abort() {
        end(discardBuffered: true)
    }

    private func end(discardBuffered: Bool) {
        var waiterToResume: CheckedContinuation<Data?, Never>?
        lock.withLock {
            if discardBuffered {
                state.chunks.removeAll()
                state.bufferedBytes = 0
                state.aborted = true
            }
            state.finished = true
            if let waiter = state.waiter {
                state.waiter = nil
                waiterToResume = waiter
            }
        }
        waiterToResume?.resume(returning: nil)
    }

    // MARK: - Consumer side

    private func next() async -> Data? {
        var shouldResumeReads = false
        let value: Data? = await withCheckedContinuation { continuation in
            var immediate: Data??
            lock.withLock {
                if !state.chunks.isEmpty {
                    let chunk = state.chunks.removeFirst()
                    state.bufferedBytes -= chunk.count
                    if state.readsPaused, state.bufferedBytes < Self.lowWatermark {
                        state.readsPaused = false
                        shouldResumeReads = true
                    }
                    immediate = .some(chunk)
                } else if state.finished {
                    immediate = .some(nil)
                } else {
                    state.waiter = continuation
                }
            }
            if let immediate {
                continuation.resume(returning: immediate)
            }
        }
        if shouldResumeReads {
            resumeReads()
        }
        return value
    }
}
#endif
