#if Server
import Foundation
import NIOCore
import NIOHTTPTypes
import Logging

extension Channel {
    /// Send an SSE message through the channel
    /// - Parameter message: The SSE message to send
    /// - Returns: An EventLoopFuture that completes when the message has been written and flushed
    func sendSSE(_ message: LosslessStringConvertible) {
        guard self.isActive else {

            return
        }

        let messageText = message.description
        var buffer = self.allocator.buffer(capacity: messageText.utf8.count)
        buffer.writeString(message.description)

        // SSE body chunk as an http-types response part — the pipeline's
        // HTTP1ToHTTPServerCodec converts it back to a NIO part on the way out.
        let part = HTTPResponsePart.body(buffer)

        // Write with promise
        self.write(part, promise: nil)
        self.flush()
    }
}
#endif
