import Foundation
import Logging
import NIOCore
import NIOHTTP1

/// A channel handler that logs both incoming and outgoing HTTP messages
public final class HTTPLogger: ChannelDuplexHandler {
    public typealias InboundIn = HTTPServerRequestPart
    public typealias InboundOut = HTTPServerRequestPart
    public typealias OutboundIn = HTTPServerResponsePart
    public typealias OutboundOut = HTTPServerResponsePart
    
    private let logger: Logger
    
    public init(label: String) {
        self.logger = Logger(label: label)
    }
    
    /// Log incoming requests and forward them to the next handler
    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let reqPart = unwrapInboundIn(data)
        
        switch reqPart {
        case .head(let head):
            var log = "➡️ HTTP REQUEST: \(head.method) \(head.uri)\n"
            log += "Headers:\n"
            head.headers.forEach { log += "  \($0.name): \($0.value)\n" }
            logger.trace("\(log)")
            
        case .body(let buffer):
            if let bodyString = buffer.getString(at: buffer.readerIndex, length: buffer.readableBytes) {
                logger.trace("➡️ HTTP REQUEST BODY:\n\(bodyString)")
            }
            
        case .end:
            break
        }
        
        // Forward the request to the next handler
        context.fireChannelRead(data)
    }
    
    /// Log outgoing responses and forward them to the next handler
    public func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let resPart = unwrapOutboundIn(data)
        
        switch resPart {
        case .head(let head):
            var log = "⬅️ HTTP RESPONSE: \(head.status.code) \(head.status.reasonPhrase)\n"
            log += "Headers:\n"
            head.headers.forEach { log += "  \($0.name): \($0.value)\n" }
            logger.trace("\(log)")
            
        case .body(let buffer):
            if case .byteBuffer(let buffer) = buffer {
                if let bodyString = buffer.getString(at: buffer.readerIndex, length: buffer.readableBytes) {
                    logger.trace("⬅️ HTTP RESPONSE BODY:\n\(bodyString)")
                }
            }
            
        case .end:
            break
        }
        
        // Forward the response to the next handler
        context.write(data, promise: promise)
    }
} 