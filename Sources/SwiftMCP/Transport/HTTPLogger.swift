import Foundation
import Logging
import NIOCore
import NIOHTTP1
import NIOConcurrencyHelpers

/// A channel handler that logs both incoming and outgoing HTTP messages
final class HTTPLogger: ChannelDuplexHandler, Sendable {
	typealias InboundIn = HTTPServerRequestPart
	typealias InboundOut = HTTPServerRequestPart
	typealias OutboundIn = HTTPServerResponsePart
	typealias OutboundOut = HTTPServerResponsePart
	
	private let httpLogger = Logger(label: "com.cocoanetics.SwiftMCP.HTTP")
	private let sseLogger = Logger(label: "com.cocoanetics.SwiftMCP.SSE")
	
	private actor State {
		// Track current request/response state
		var currentRequestHead: HTTPRequestHead?
		var currentRequestBody = ""
		var currentResponseHead: HTTPResponseHead?
		var currentResponseBody = ""
		var isSSEConnection = false
		
		func reset() {
			currentRequestHead = nil
			currentRequestBody = ""
			currentResponseHead = nil
			currentResponseBody = ""
			isSSEConnection = false
		}
		
		func setSSEConnection(_ isSSE: Bool) {
			isSSEConnection = isSSE
		}
		
		func isSSE() -> Bool {
			isSSEConnection
		}
		
		func setRequestHead(_ head: HTTPRequestHead) {
			currentRequestHead = head
			currentRequestBody = ""
		}
		
		func appendRequestBody(_ str: String) {
			currentRequestBody += str
		}
		
		func clearRequest() {
			currentRequestHead = nil
			currentRequestBody = ""
		}
		
		func setResponseHead(_ head: HTTPResponseHead) {
			currentResponseHead = head
			currentResponseBody = ""
		}
		
		func appendResponseBody(_ str: String) {
			currentResponseBody += str
		}
		
		func clearResponse() {
			currentResponseHead = nil
			currentResponseBody = ""
		}
		
		func getCurrentRequestState() -> (head: HTTPRequestHead?, body: String) {
			(currentRequestHead, currentRequestBody)
		}
		
		func getCurrentResponseState() -> (head: HTTPResponseHead?, body: String) {
			(currentResponseHead, currentResponseBody)
		}
	}
	
	private let state = State()
	
	/// Log incoming requests and forward them to the next handler
	func channelRead(context: ChannelHandlerContext, data: NIOAny) {
		let reqPart = unwrapInboundIn(data)
		let promise = context.eventLoop.makePromise(of: Void.self)
		
		promise.completeWithTask { [self] in
			switch reqPart {
			case .head(let head):
				// Check if this is an SSE connection
				if head.uri.hasPrefix("/sse") {
					await state.setSSEConnection(true)
				}
				
				// Log previous request if exists
				let (currentHead, currentBody) = await state.getCurrentRequestState()
				if let currentHead = currentHead {
					var log = "\(currentHead.method) \(currentHead.uri) HTTP/\(currentHead.version.major).\(currentHead.version.minor)\n"
					currentHead.headers.forEach { log += "\($0.name): \($0.value)\n" }
					log += "\n"  // Empty line after headers
					
					if !currentBody.isEmpty {
						log += currentBody + "\n"
					}
					
					httpLogger.info("\(log)")
				}
				
				await state.setRequestHead(head)
				
			case .body(let buffer):
				if let str = buffer.getString(at: buffer.readerIndex, length: buffer.readableBytes) {
					await state.appendRequestBody(str)
				}
				
			case .end:
				let (head, body) = await state.getCurrentRequestState()
				if let head = head {
					var log = "\(head.method) \(head.uri) HTTP/\(head.version.major).\(head.version.minor)\n"
					head.headers.forEach { log += "\($0.name): \($0.value)\n" }
					log += "\n"  // Empty line after headers
					
					if !body.isEmpty {
						log += body + "\n"
					}
					
					httpLogger.info("\(log)")
				}
				await state.clearRequest()
			}
		}
		
		promise.futureResult.whenComplete { _ in
			context.fireChannelRead(data)
		}
	}
	
	/// Log outgoing responses and forward them to the next handler
	func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
		let resPart = unwrapOutboundIn(data)
		let writePromise = context.eventLoop.makePromise(of: Void.self)
		
		writePromise.completeWithTask { [self] in
			switch resPart {
			case .head(let head):
				// For SSE connections, only log the initial response headers
				if await state.isSSE() {
					var log = "HTTP/\(head.version.major).\(head.version.minor) \(head.status.code) \(head.status.reasonPhrase)\n"
					head.headers.forEach { log += "\($0.name): \($0.value)\n" }
					log += "\n"
					sseLogger.info("Connection Established:\n\(log)")
				} else {
					// Log previous response if exists
					let (currentHead, currentBody) = await state.getCurrentResponseState()
					if let currentHead = currentHead {
						var log = "HTTP/\(currentHead.version.major).\(currentHead.version.minor) \(currentHead.status.code) \(currentHead.status.reasonPhrase)\n"
						currentHead.headers.forEach { log += "\($0.name): \($0.value)\n" }
						log += "\n"  // Empty line after headers
						
						if !currentBody.isEmpty {
							log += currentBody + "\n"
						}
						
						httpLogger.info("\(log)")
					}
					await state.setResponseHead(head)
				}
				
			case .body(let body):
				if case .byteBuffer(let buffer) = body {
					if let str = buffer.getString(at: buffer.readerIndex, length: buffer.readableBytes) {
						if await state.isSSE() {
							// For SSE, log each message immediately
							sseLogger.trace("\(str)")
						} else {
							await state.appendResponseBody(str)
						}
					}
				}
				
			case .end:
				if !(await state.isSSE()) {
					let (head, body) = await state.getCurrentResponseState()
					if let head = head {
						var log = "HTTP/\(head.version.major).\(head.version.minor) \(head.status.code) \(head.status.reasonPhrase)\n"
						head.headers.forEach { log += "\($0.name): \($0.value)\n" }
						log += "\n"  // Empty line after headers
						
						if !body.isEmpty {
							log += body + "\n"
						}
						
						httpLogger.info("\(log)")
					}
					await state.clearResponse()
				}
			}
		}
		
		writePromise.futureResult.whenComplete { _ in
			context.write(data, promise: promise)
		}
	}
	
	func flush(context: ChannelHandlerContext) {
		context.flush()
	}
	
	func handlerAdded(context: ChannelHandlerContext) {
		let promise = context.eventLoop.makePromise(of: Void.self)
		promise.completeWithTask { [self] in
			await state.reset()
		}
	}
	
	func handlerRemoved(context: ChannelHandlerContext) {
		let promise = context.eventLoop.makePromise(of: Void.self)
		promise.completeWithTask { [self] in
			// Log any pending messages
			let (reqHead, reqBody) = await state.getCurrentRequestState()
			if let head = reqHead {
				var log = "\(head.method) \(head.uri) HTTP/\(head.version.major).\(head.version.minor)\n"
				head.headers.forEach { log += "\($0.name): \($0.value)\n" }
				log += "\n"  // Empty line after headers
				
				if !reqBody.isEmpty {
					log += reqBody + "\n"
				}
				
				httpLogger.info("\(log)")
			}
			
			if !(await state.isSSE()) {
				let (resHead, resBody) = await state.getCurrentResponseState()
				if let head = resHead {
					var log = "HTTP/\(head.version.major).\(head.version.minor) \(head.status.code) \(head.status.reasonPhrase)\n"
					head.headers.forEach { log += "\($0.name): \($0.value)\n" }
					log += "\n"  // Empty line after headers
					
					if !resBody.isEmpty {
						log += resBody + "\n"
					}
					
					httpLogger.info("\(log)")
				}
			}
			
			// Clear state
			await state.reset()
		}
	}
}
