import Foundation
import NIOCore
import NIOHTTP1

extension Channel {
    /// Send an SSE message through the channel
    /// - Parameter message: The SSE message to send
    /// - Returns: An EventLoopFuture that completes when the message has been written and flushed
    func sendSSE(_ message: SSEMessage) -> EventLoopFuture<Void> {
        let messageText = message.description
        var buffer = self.allocator.buffer(capacity: messageText.utf8.count)
		buffer.writeString(message.description)
        
        let part = HTTPServerResponsePart.body(.byteBuffer(buffer))
        return self.writeAndFlush(part)
    }
} 
