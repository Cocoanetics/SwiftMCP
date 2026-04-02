import NIOHTTP1
import NIOCore
import Foundation

/// Represents the state of an HTTP request being processed.
///
/// The state machine always streams body chunks via an `AsyncStream<Data>` continuation.
/// The dispatch layer decides whether to collect the stream into `Data` (for buffered
/// handlers) or forward it directly (for streaming handlers).
enum RequestState {
    case idle
    /// Body chunks are being yielded into the continuation.
    case streaming(head: HTTPRequestHead, continuation: AsyncStream<Data>.Continuation, bytesWritten: Int)
    case rejected
}
