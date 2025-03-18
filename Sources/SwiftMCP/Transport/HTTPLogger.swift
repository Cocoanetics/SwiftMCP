import Foundation
import Logging
import NIOCore
import NIOHTTP1
import NIOConcurrencyHelpers

/// A channel handler that logs both incoming and outgoing HTTP messages
public final class HTTPLogger: ChannelDuplexHandler {
	public typealias InboundIn = HTTPServerRequestPart
	public typealias InboundOut = HTTPServerRequestPart
	public typealias OutboundIn = HTTPServerResponsePart
	public typealias OutboundOut = HTTPServerResponsePart

	private let httpLogger = Logger(label: "com.cocoanetics.SwiftMCP.HTTP")
	private let sseLogger = Logger(label: "com.cocoanetics.SwiftMCP.SSE")
	private let lock = NIOLock()
	
	// Track current request/response state
	private var currentRequestHead: HTTPRequestHead?
	private var currentRequestBody = ""
	private var currentResponseHead: HTTPResponseHead?
	private var currentResponseBody = ""
	
	/// Log incoming requests and forward them to the next handler
	public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
		let reqPart = unwrapInboundIn(data)
		
		lock.withLock {
			switch reqPart {
			case .head(let head):
				// Log previous request if exists
				logCurrentRequest()
				
				currentRequestHead = head
				currentRequestBody = ""
				
			case .body(let buffer):
				if let str = buffer.getString(at: buffer.readerIndex, length: buffer.readableBytes) {
					currentRequestBody += str
				}
				
			case .end:
				logCurrentRequest()
				currentRequestHead = nil
				currentRequestBody = ""
			}
		}
		
		context.fireChannelRead(data)
	}
	
	/// Log outgoing responses and forward them to the next handler
	public func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
		let resPart = unwrapOutboundIn(data)
		
		lock.withLock {
			switch resPart {
			case .head(let head):
				// Log previous response if exists
				logCurrentResponse()
				
				currentResponseHead = head
				currentResponseBody = ""
				
			case .body(let body):
				if case .byteBuffer(let buffer) = body {
					if let str = buffer.getString(at: buffer.readerIndex, length: buffer.readableBytes) {
						// Check if this is an SSE response
						if isSSEResponse {
							logSSEMessage(str)
						} else {
							currentResponseBody += str
						}
					}
				}
				
			case .end:
				logCurrentResponse()
				currentResponseHead = nil
				currentResponseBody = ""
			}
		}
		
		context.write(data, promise: promise)
	}
	
	public func flush(context: ChannelHandlerContext) {
		context.flush()
	}
	
	private var isSSEResponse: Bool {
		currentResponseHead?.headers.first(name: "Content-Type") == "text/event-stream"
	}
	
	private func logCurrentRequest() {
		guard let head = currentRequestHead else { return }
		
		// Determine if this is an SSE request
		let isSSE = head.uri.hasPrefix("/sse")
		
		var log = "\(head.method) \(head.uri) HTTP/\(head.version.major).\(head.version.minor)\n"
		head.headers.forEach { log += "\($0.name): \($0.value)\n" }
		log += "\n"  // Empty line after headers
		
		if !currentRequestBody.isEmpty {
			log += currentRequestBody + "\n"
		}
		
		if isSSE {
			sseLogger.trace("\(log)")
		} else {
			httpLogger.trace("\(log)")
		}
	}
	
	private func logCurrentResponse() {
		guard let head = currentResponseHead else { return }
		
		// Skip logging SSE responses as they are handled separately
		if isSSEResponse {
			return
		}
		
		var log = "HTTP/\(head.version.major).\(head.version.minor) \(head.status.code) \(head.status.reasonPhrase)\n"
		head.headers.forEach { log += "\($0.name): \($0.value)\n" }
		log += "\n"  // Empty line after headers
		
		if !currentResponseBody.isEmpty {
			log += currentResponseBody + "\n"
		}
		
		httpLogger.trace("\(log)")
	}
	
	private func logSSEMessage(_ message: String) {
		sseLogger.info("""
			SSE Message:
			- Raw: \(message)
			- Length: \(message.utf8.count)
			- Timestamp: \(Date())
			""")
	}
	
	public func handlerAdded(context: ChannelHandlerContext) {
		lock.withLock {
			currentRequestHead = nil
			currentRequestBody = ""
			currentResponseHead = nil
			currentResponseBody = ""
		}
	}
	
	public func handlerRemoved(context: ChannelHandlerContext) {
		lock.withLock {
			// Log any pending messages
			logCurrentRequest()
			logCurrentResponse()
			
			// Clear state
			currentRequestHead = nil
			currentRequestBody = ""
			currentResponseHead = nil
			currentResponseBody = ""
		}
	}
}
