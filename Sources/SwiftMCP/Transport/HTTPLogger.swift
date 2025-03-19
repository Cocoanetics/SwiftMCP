	import Foundation
	import Logging
	import NIOCore
	import NIOHTTP1
	import NIOConcurrencyHelpers

	/// A channel handler that logs both incoming and outgoing HTTP messages
	final class HTTPLogger: ChannelDuplexHandler {
		typealias InboundIn = HTTPServerRequestPart
		typealias InboundOut = HTTPServerRequestPart
		typealias OutboundIn = HTTPServerResponsePart
		typealias OutboundOut = HTTPServerResponsePart

		private lazy var httpLogger = Logger(label: "com.cocoanetics.SwiftMCP.HTTP")
		private lazy var sseLogger = Logger(label: "com.cocoanetics.SwiftMCP.SSE")
		private let lock = NIOLock()
		
		// Track current request/response state
		private var currentRequestHead: HTTPRequestHead?
		private var currentRequestBody = ""
		private var currentResponseHead: HTTPResponseHead?
		private var currentResponseBody = ""
		private var isSSEConnection = false
		
		/// Log incoming requests and forward them to the next handler
		func channelRead(context: ChannelHandlerContext, data: NIOAny) {
			let reqPart = unwrapInboundIn(data)
			
			lock.withLock {
				switch reqPart {
				case .head(let head):
					// Check if this is an SSE connection
					if head.uri.hasPrefix("/sse") {
						isSSEConnection = true
					}
					
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
		func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
			let resPart = unwrapOutboundIn(data)
			
			lock.withLock {
				switch resPart {
				case .head(let head):
					// For SSE connections, only log the initial response headers
					if isSSEConnection {
						var log = "HTTP/\(head.version.major).\(head.version.minor) \(head.status.code) \(head.status.reasonPhrase)\n"
						head.headers.forEach { log += "\($0.name): \($0.value)\n" }
						log += "\n"
						sseLogger.info("Connection Established:\n\(log)")
					} else {
						// Log previous response if exists
						logCurrentResponse()
						currentResponseHead = head
						currentResponseBody = ""
					}
					
				case .body(let body):
					if case .byteBuffer(let buffer) = body {
						if let str = buffer.getString(at: buffer.readerIndex, length: buffer.readableBytes) {
							if isSSEConnection {
								// For SSE, log each message immediately
								sseLogger.trace("\(str)")
							} else {
								currentResponseBody += str
							}
						}
					}
					
				case .end:
					if !isSSEConnection {
						logCurrentResponse()
						currentResponseHead = nil
						currentResponseBody = ""
					}
				}
			}
			
			context.write(data, promise: promise)
		}
		
		func flush(context: ChannelHandlerContext) {
			context.flush()
		}
		
		private func logCurrentRequest() {
			guard let head = currentRequestHead else { return }
			
			var log = "\(head.method) \(head.uri) HTTP/\(head.version.major).\(head.version.minor)\n"
			head.headers.forEach { log += "\($0.name): \($0.value)\n" }
			log += "\n"  // Empty line after headers
			
			if !currentRequestBody.isEmpty {
				log += currentRequestBody + "\n"
			}
			
			httpLogger.info("\(log)")
		}
		
		private func logCurrentResponse() {
			guard let head = currentResponseHead else { return }
			
			var log = "HTTP/\(head.version.major).\(head.version.minor) \(head.status.code) \(head.status.reasonPhrase)\n"
			head.headers.forEach { log += "\($0.name): \($0.value)\n" }
			log += "\n"  // Empty line after headers
			
			if !currentResponseBody.isEmpty {
				log += currentResponseBody + "\n"
			}
			
			httpLogger.info("\(log)")
		}
		
		func handlerAdded(context: ChannelHandlerContext) {
			lock.withLock {
				currentRequestHead = nil
				currentRequestBody = ""
				currentResponseHead = nil
				currentResponseBody = ""
				isSSEConnection = false
			}
		}
		
		func handlerRemoved(context: ChannelHandlerContext) {
			lock.withLock {
				// Log any pending messages
				logCurrentRequest()
				if !isSSEConnection {
					logCurrentResponse()
				}
				
				// Clear state
				currentRequestHead = nil
				currentRequestBody = ""
				currentResponseHead = nil
				currentResponseBody = ""
				isSSEConnection = false
			}
		}
	}
