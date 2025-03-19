import Foundation
import NIOCore
import NIOHTTP1
import Logging

extension Channel {
    /// Send an SSE message through the channel
    /// - Parameter message: The SSE message to send
    /// - Returns: An EventLoopFuture that completes when the message has been written and flushed
    func sendSSE(_ message: LosslessStringConvertible) {
        guard self.isActive else {
            Logger(label: "com.cocoanetics.SwiftMCP.Transport").warning("Attempted to send SSE message on inactive channel")
            return
        }
        
        let messageText = message.description
        var buffer = self.allocator.buffer(capacity: messageText.utf8.count)
        buffer.writeString(message.description)
        
        let part = HTTPServerResponsePart.body(.byteBuffer(buffer))
        
        // Create a promise to track the write operation
        let promise = self.eventLoop.makePromise(of: Void.self)
        
        // Set up promise completion handler
        promise.futureResult.whenComplete { result in
            switch result {
            case .success:
                Logger(label: "com.cocoanetics.SwiftMCP.Transport").debug("SSE message sent successfully")
            case .failure(let error):
                Logger(label: "com.cocoanetics.SwiftMCP.Transport").error("Failed to send SSE message: \(error)")
                // Close the channel on write failure
                self.close(promise: nil)
            }
        }
        
        // Write with promise
        self.write(part, promise: promise)
        self.flush()
    }
} 
