#if Server
import Foundation
import HTTPTypes

/// Represents the state of an HTTP request being processed.
///
/// The state machine always streams body chunks through an
/// ``InboundBodyBuffer``, which bounds buffering with read watermarks. The
/// dispatch layer decides whether to collect the stream into `Data` (for
/// buffered handlers) or forward it directly (for streaming handlers).
enum RequestState {
    case idle
    /// Body chunks are being appended to the buffer.
    case streaming(head: HTTPRequest, body: InboundBodyBuffer, bytesWritten: Int)
    case rejected
}
#endif
