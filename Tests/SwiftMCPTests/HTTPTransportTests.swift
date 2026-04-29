import Testing
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import SwiftMCP

@MCPServer(name: "UploadCapableServer")
private final class UploadCapableServer {
	@MCPTool(description: "Health check")
	func ping() -> String {
		"pong"
	}
}

extension UploadCapableServer: MCPFileUploadHandling {}

@MCPServer(name: "ResumableServer")
private final class ResumableServer {
	@MCPTool(description: "Emits progress before returning pong")
	func slowPing() async -> String {
		await RequestContext.current?.reportProgress(0.2, total: 1.0, message: "starting")
		try? await Task.sleep(nanoseconds: 150_000_000)
		await RequestContext.current?.reportProgress(0.6, total: 1.0, message: "middle")
		try? await Task.sleep(nanoseconds: 150_000_000)
		return "pong"
	}
}

@Suite("HTTP Transport Integration")
struct HTTPTransportTests {

	/// Create a transport, start it, and return the base URL.
	private func startTransport(
		server: some MCPServer = Calculator(),
		retentionInterval: TimeInterval? = nil
	) async throws -> (HTTPSSETransport, URL) {
		let transport = HTTPSSETransport(server: server, host: "127.0.0.1", port: 0)
		if let retentionInterval {
			transport.streamRetentionInterval = retentionInterval
		}
		try await transport.start()
		let baseURL = URL(string: "http://127.0.0.1:\(transport.port)")!
		return (transport, baseURL)
	}

	/// Encode a JSON-RPC message to Data.
	private func encode(_ message: JSONRPCMessage) throws -> Data {
		try JSONEncoder().encode(message)
	}

	/// Decode a JSON-RPC message from Data.
	private func decode(_ data: Data) throws -> JSONRPCMessage {
		try JSONDecoder().decode(JSONRPCMessage.self, from: data)
	}

	/// Build the standard initialize request.
	private func initializeRequest(id: Int = 1) -> JSONRPCMessage {
		.request(
			id: id,
			method: "initialize",
			params: [
				"protocolVersion": .string("2025-11-25"),
				"capabilities": .object([:]),
				"clientInfo": .object([
					"name": .string("TestClient"),
					"version": .string("1.0")
				])
			]
		)
	}

	private func streamablePOSTRequest(
		url: URL,
		message: JSONRPCMessage,
		sessionID: String? = nil,
		protocolVersion: String = "2025-11-25"
	) throws -> URLRequest {
		var request = URLRequest(url: url)
		request.httpMethod = "POST"
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
		request.setValue(protocolVersion, forHTTPHeaderField: "MCP-Protocol-Version")
		if let sessionID {
			request.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id")
		}
		request.httpBody = try encode(message)
		return request
	}

	private func generalSSERequest(
		url: URL,
		sessionID: String,
		lastEventID: String? = nil,
		protocolVersion: String = "2025-11-25"
	) -> URLRequest {
		var request = URLRequest(url: url)
		request.httpMethod = "GET"
		request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
		request.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id")
		request.setValue(protocolVersion, forHTTPHeaderField: "MCP-Protocol-Version")
		if let lastEventID {
			request.setValue(lastEventID, forHTTPHeaderField: "Last-Event-ID")
		}
		return request
	}

	private func readFiniteSSEResponse(_ request: URLRequest) async throws -> (HTTPURLResponse, [SSEClientMessage]) {
		#if canImport(FoundationNetworking)
		let delegate = SSEStreamingDelegate { _ in }
		let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
		let task = session.dataTask(with: request)
		task.resume()

		var events: [SSEClientMessage] = []
		for try await message in delegate.lines.sseMessages() {
			events.append(message)
		}

		guard let httpResponse = delegate.response as? HTTPURLResponse else {
			throw TestError("Expected HTTPURLResponse")
		}

		return (httpResponse, events)
		#else
		let session = URLSession(configuration: .ephemeral)
		let (bytes, response) = try await session.bytes(for: request)
		guard let httpResponse = response as? HTTPURLResponse else {
			throw TestError("Expected HTTPURLResponse")
		}

		var events: [SSEClientMessage] = []
		for try await message in bytes.lines.sseMessages() {
			events.append(message)
		}

		return (httpResponse, events)
		#endif
	}

	private func openStreamingRequest(_ request: URLRequest) -> StreamCapture {
		let responseBox = Box<HTTPURLResponse?>(nil)
		let eventsBox = Box<[SSEClientMessage]>([])

		let task = Task {
			#if canImport(FoundationNetworking)
			let delegate = SSEStreamingDelegate { response in
				responseBox.value = response as? HTTPURLResponse
			}
			let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
			let dataTask = session.dataTask(with: request)
			dataTask.resume()
			for try await message in delegate.lines.sseMessages() {
				eventsBox.value.append(message)
			}
			#else
			let session = URLSession(configuration: .ephemeral)
			let (bytes, response) = try await session.bytes(for: request)
			responseBox.value = response as? HTTPURLResponse
			for try await message in bytes.lines.sseMessages() {
				eventsBox.value.append(message)
			}
			#endif
		}

		return StreamCapture(response: responseBox, events: eventsBox, task: task)
	}

	private func waitForCondition(
		timeoutNanoseconds: UInt64 = 2_000_000_000,
		pollNanoseconds: UInt64 = 50_000_000,
		_ condition: @escaping @Sendable () -> Bool
	) async -> Bool {
		let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
		while DispatchTime.now().uptimeNanoseconds < deadline {
			if condition() {
				return true
			}
			try? await Task.sleep(nanoseconds: pollNanoseconds)
		}
		return condition()
	}

	private func initializeSession(url: URL) async throws -> (String, [SSEClientMessage]) {
		let request = try streamablePOSTRequest(url: url, message: initializeRequest())
		let (response, events) = try await readFiniteSSEResponse(request)
		guard let sessionID = response.value(forHTTPHeaderField: "Mcp-Session-Id") else {
			throw TestError("Expected Mcp-Session-Id header")
		}
		return (sessionID, events)
	}

	private func decodeEventMessage(_ event: SSEClientMessage) throws -> JSONRPCMessage? {
		guard !event.data.isEmpty else {
			return nil
		}
		return try decode(Data(event.data.utf8))
	}

	private func responseEvent(_ events: [SSEClientMessage], id: Int) -> SSEClientMessage? {
		events.first { event in
			guard let message = try? decodeEventMessage(event),
				  case .response(let response) = message else {
				return false
			}
			return response.id == .int(id)
		}
	}

	private func notificationEvent(_ events: [SSEClientMessage], method: String) -> SSEClientMessage? {
		events.first { event in
			guard let message = try? decodeEventMessage(event),
				  case .notification(let notification) = message else {
				return false
			}
			return notification.method == method
		}
	}

	private func errorResponseEvent(_ events: [SSEClientMessage], id: Int) -> SSEClientMessage? {
		events.first { event in
			guard let message = try? decodeEventMessage(event),
				  case .errorResponse(let errorResponse) = message else {
				return false
			}
			return errorResponse.id == .int(id)
		}
	}

	// MARK: - Modern Streamable HTTP

	@Test("POST /mcp: initialize returns SSE response stream")
	func modernInitialize() async throws {
		#if canImport(FoundationNetworking)
		return
		#else
		let (transport, baseURL) = try await startTransport()
		defer { Task { try? await transport.stop() } }

		let (response, events) = try await readFiniteSSEResponse(
			try streamablePOSTRequest(
				url: baseURL.appendingPathComponent("mcp"),
				message: initializeRequest()
			)
		)

		#expect(response.statusCode == 200)
		#expect(response.value(forHTTPHeaderField: "Content-Type")?.contains("text/event-stream") == true)
		#expect(response.value(forHTTPHeaderField: "Mcp-Session-Id") != nil)

		let primingEvent = try #require(events.first)
		#expect(primingEvent.id != nil)
		#expect(primingEvent.data == "")

		let initEvent = try #require(responseEvent(events, id: 1))
		let message = try #require(try decodeEventMessage(initEvent))
		guard case .response(let responseData) = message,
			  let result = responseData.result,
			  let protocolVersion = result["protocolVersion"]?.stringValue else {
			Issue.record("Expected initialize response payload")
			return
		}

		#expect(protocolVersion == "2025-11-25")
		#endif
	}

	@Test("POST /mcp: initialize preserves negotiated fallback protocol version")
	func initializeNegotiatesFallbackProtocolVersion() async throws {
		#if canImport(FoundationNetworking)
		return
		#else
		let (transport, baseURL) = try await startTransport()
		defer { Task { try? await transport.stop() } }

		let request = try streamablePOSTRequest(
			url: baseURL.appendingPathComponent("mcp"),
			message: .request(
				id: 1,
				method: "initialize",
				params: [
					"protocolVersion": .string("2025-03-26"),
					"capabilities": .object([:]),
					"clientInfo": .object([
						"name": .string("TestClient"),
						"version": .string("1.0")
					])
				]
			),
			protocolVersion: "2025-03-26"
		)

		let (response, events) = try await readFiniteSSEResponse(request)
		#expect(response.statusCode == 200)

		let initEvent = try #require(responseEvent(events, id: 1))
		let message = try #require(try decodeEventMessage(initEvent))
		guard case .response(let responseData) = message,
			  let result = responseData.result,
			  let protocolVersion = result["protocolVersion"]?.stringValue else {
			Issue.record("Expected initialize response payload")
			return
		}

		#expect(protocolVersion == "2025-03-26")
		#endif
	}

	@Test("POST /mcp: initialize preserves negotiated intermediate protocol version")
	func initializeNegotiatesIntermediateProtocolVersion() async throws {
		#if canImport(FoundationNetworking)
		return
		#else
		let (transport, baseURL) = try await startTransport()
		defer { Task { try? await transport.stop() } }

		let request = try streamablePOSTRequest(
			url: baseURL.appendingPathComponent("mcp"),
			message: .request(
				id: 1,
				method: "initialize",
				params: [
					"protocolVersion": .string("2025-06-18"),
					"capabilities": .object([:]),
					"clientInfo": .object([
						"name": .string("TestClient"),
						"version": .string("1.0")
					])
				]
			),
			protocolVersion: "2025-06-18"
		)

		let (response, events) = try await readFiniteSSEResponse(request)
		#expect(response.statusCode == 200)

		let initEvent = try #require(responseEvent(events, id: 1))
		let message = try #require(try decodeEventMessage(initEvent))
		guard case .response(let responseData) = message,
			  let result = responseData.result,
			  let protocolVersion = result["protocolVersion"]?.stringValue else {
			Issue.record("Expected initialize response payload")
			return
		}

		#expect(protocolVersion == "2025-06-18")
		#endif
	}

	@Test("POST /mcp: initialize rejects unsupported protocol version")
	func initializeRejectsUnsupportedProtocolVersion() async throws {
		#if canImport(FoundationNetworking)
		return
		#else
		let (transport, baseURL) = try await startTransport()
		defer { Task { try? await transport.stop() } }

		let request = try streamablePOSTRequest(
			url: baseURL.appendingPathComponent("mcp"),
			message: .request(
				id: 1,
				method: "initialize",
				params: [
					"protocolVersion": .string("2024-11-05"),
					"capabilities": .object([:]),
					"clientInfo": .object([
						"name": .string("TestClient"),
						"version": .string("1.0")
					])
				]
			)
		)

		let (response, events) = try await readFiniteSSEResponse(request)
		#expect(response.statusCode == 200)

		let initEvent = try #require(errorResponseEvent(events, id: 1))
		let message = try #require(try decodeEventMessage(initEvent))
		guard case .errorResponse(let errorData) = message else {
			Issue.record("Expected initialize error response")
			return
		}

		#expect(errorData.error.code == -32602)
		#expect(errorData.error.message.contains("Unsupported protocol version"))
		#endif
	}

	@Test("POST /mcp: request stream returns response for existing session")
	func modernPing() async throws {
		#if canImport(FoundationNetworking)
		return
		#else
		let (transport, baseURL) = try await startTransport()
		defer { Task { try? await transport.stop() } }

		let url = baseURL.appendingPathComponent("mcp")
		let (sessionID, _) = try await initializeSession(url: url)

		let (response, events) = try await readFiniteSSEResponse(
			try streamablePOSTRequest(
				url: url,
				message: .request(id: 2, method: "ping"),
				sessionID: sessionID
			)
		)

		#expect(response.statusCode == 200)
		#expect(response.value(forHTTPHeaderField: "Mcp-Session-Id") == sessionID)
		#expect(responseEvent(events, id: 2) != nil)
		#endif
	}

	@Test("POST /mcp: missing session on non-initialize returns 400 without creating a session")
	func modernNonInitializeWithoutSessionRejected() async throws {
		let (transport, baseURL) = try await startTransport()
		defer { Task { try? await transport.stop() } }

		let session = URLSession(configuration: .ephemeral)
		var request = URLRequest(url: baseURL.appendingPathComponent("mcp"))
		request.httpMethod = "POST"
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
		request.httpBody = try encode(JSONRPCMessage.request(id: 1, method: "ping"))

		let (_, response) = try await session.data(for: request)
		let http = response as! HTTPURLResponse
		#expect(http.statusCode == 400)
		#expect(http.value(forHTTPHeaderField: "Mcp-Session-Id") == nil)
		#expect(await transport.sessionManager.sessionIDs.isEmpty)
	}

	@Test("POST /mcp: unknown session returns 404")
	func modernUnknownSessionRejected() async throws {
		let (transport, baseURL) = try await startTransport()
		defer { Task { try? await transport.stop() } }

		let session = URLSession(configuration: .ephemeral)
		var request = URLRequest(url: baseURL.appendingPathComponent("mcp"))
		request.httpMethod = "POST"
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
		request.setValue(UUID().uuidString, forHTTPHeaderField: "Mcp-Session-Id")
		request.httpBody = try encode(JSONRPCMessage.request(id: 1, method: "ping"))

		let (_, response) = try await session.data(for: request)
		let http = response as! HTTPURLResponse
		#expect(http.statusCode == 404)
		#expect(await transport.sessionManager.sessionIDs.isEmpty)
	}

	@Test("GET /mcp: missing session returns 400")
	func modernGeneralStreamRequiresSession() async throws {
		let (transport, baseURL) = try await startTransport()
		defer { Task { try? await transport.stop() } }

		let session = URLSession(configuration: .ephemeral)
		var request = URLRequest(url: baseURL.appendingPathComponent("mcp"))
		request.httpMethod = "GET"
		request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
		let (_, response) = try await session.data(for: request)
		#expect((response as! HTTPURLResponse).statusCode == 400)
	}

	@Test("GET /mcp: unknown session returns 404")
	func unknownModernSSESession() async throws {
		let (transport, baseURL) = try await startTransport()
		defer { Task { try? await transport.stop() } }

		let session = URLSession(configuration: .ephemeral)
		let request = generalSSERequest(
			url: baseURL.appendingPathComponent("mcp"),
			sessionID: UUID().uuidString
		)
		let (_, response) = try await session.data(for: request)
		#expect((response as! HTTPURLResponse).statusCode == 404)
	}

	@Test("GET /mcp: general stream primes and can resume missed notifications")
	func generalStreamResume() async throws {
		#if canImport(FoundationNetworking)
		return
		#else
		let (transport, baseURL) = try await startTransport()
		defer { Task { try? await transport.stop() } }

		let url = baseURL.appendingPathComponent("mcp")
		let (sessionID, _) = try await initializeSession(url: url)
		let capture = openStreamingRequest(generalSSERequest(url: url, sessionID: sessionID))

		let primed = await waitForCondition {
			capture.response.value != nil && !capture.events.value.isEmpty
		}
		#expect(primed)

		let primingEvent = try #require(capture.events.value.first)
		let primingEventID = try #require(primingEvent.id)
		capture.task.cancel()

		try? await Task.sleep(nanoseconds: 100_000_000)
		await transport.broadcastToolsListChanged()
		try? await Task.sleep(nanoseconds: 50_000_000)

		let resumed = openStreamingRequest(generalSSERequest(url: url, sessionID: sessionID, lastEventID: primingEventID))
		let resumedReceived = await waitForCondition {
			notificationEvent(resumed.events.value, method: "notifications/tools/list_changed") != nil
		}
		#expect(resumedReceived)

		let notification = try #require(notificationEvent(resumed.events.value, method: "notifications/tools/list_changed"))
		#expect(notification.id != nil)
		resumed.task.cancel()
		#endif
	}

	@Test("POST /mcp: request stream can resume after disconnect")
	func requestStreamResume() async throws {
		#if canImport(FoundationNetworking)
		return
		#else
		let (transport, baseURL) = try await startTransport(server: ResumableServer())
		defer { Task { try? await transport.stop() } }

		let url = baseURL.appendingPathComponent("mcp")
		let (sessionID, _) = try await initializeSession(url: url)

		let requestCapture = openStreamingRequest(
			try streamablePOSTRequest(
				url: url,
				message: .request(
					id: 2,
					method: "tools/call",
					params: [
						"name": .string("slowPing"),
						"arguments": .object([:]),
						"_meta": .object([
							"progressToken": .string("slow-request")
						])
					]
				),
				sessionID: sessionID
			)
		)

		let sawProgress = await waitForCondition {
			notificationEvent(requestCapture.events.value, method: "notifications/progress") != nil
		}
		#expect(sawProgress)

		let lastSeenEventID = try #require(requestCapture.events.value.last?.id)
		requestCapture.task.cancel()

		try? await Task.sleep(nanoseconds: 500_000_000)

		let resumedRequest = try await readFiniteSSEResponse(
			generalSSERequest(url: url, sessionID: sessionID, lastEventID: lastSeenEventID)
		)

		#expect(notificationEvent(resumedRequest.1, method: "notifications/progress") != nil)
		#expect(responseEvent(resumedRequest.1, id: 2) != nil)
		#endif
	}

	@Test("Multiple general streams route unsolicited notifications only to the newest active stream")
	func multipleGeneralStreamsPrimarySelection() async throws {
		#if canImport(FoundationNetworking)
		return
		#else
		let (transport, baseURL) = try await startTransport()
		defer { Task { try? await transport.stop() } }

		let url = baseURL.appendingPathComponent("mcp")
		let (sessionID, _) = try await initializeSession(url: url)

		let streamA = openStreamingRequest(generalSSERequest(url: url, sessionID: sessionID))
		let streamAReady = await waitForCondition {
			!streamA.events.value.isEmpty
		}
		#expect(streamAReady)

		let streamB = openStreamingRequest(generalSSERequest(url: url, sessionID: sessionID))
		let streamBReady = await waitForCondition {
			!streamB.events.value.isEmpty
		}
		#expect(streamBReady)

		await transport.broadcastPromptsListChanged()
		let received = await waitForCondition {
			notificationEvent(streamB.events.value, method: "notifications/prompts/list_changed") != nil
		}
		#expect(received)
		#expect(notificationEvent(streamA.events.value, method: "notifications/prompts/list_changed") == nil)

		streamA.task.cancel()
		streamB.task.cancel()
		#endif
	}

	// MARK: - Legacy SSE Protocol

	@Test("Legacy SSE: connect, get endpoint, initialize, ping")
	func legacySSEFullFlow() async throws {
		#if canImport(FoundationNetworking)
		return
		#else
		let (transport, baseURL) = try await startTransport()
		defer { Task { try? await transport.stop() } }

		let capture = openStreamingRequest({
			var request = URLRequest(url: baseURL.appendingPathComponent("sse"))
			request.httpMethod = "GET"
			request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
			return request
		}())

		let hasEndpoint = await waitForCondition {
			notificationEvent(capture.events.value, method: "endpoint") != nil || capture.events.value.contains { $0.event == "endpoint" }
		}

		let endpointEvent = try #require(capture.events.value.first(where: { $0.event == "endpoint" }))
		let messagesURL = try #require(URL(string: endpointEvent.data))
		#expect(hasEndpoint)
		#expect(messagesURL.path.hasPrefix("/messages/"))

		let postSession = URLSession(configuration: .ephemeral)
		var initRequest = URLRequest(url: messagesURL)
		initRequest.httpMethod = "POST"
		initRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
		initRequest.httpBody = try encode(initializeRequest())
		let (_, initResponse) = try await postSession.data(for: initRequest)
		#expect((initResponse as! HTTPURLResponse).statusCode == 202)

		let initDelivered = await waitForCondition {
			responseEvent(capture.events.value, id: 1) != nil
		}
		#expect(initDelivered)

		var pingRequest = URLRequest(url: messagesURL)
		pingRequest.httpMethod = "POST"
		pingRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
		pingRequest.httpBody = try encode(JSONRPCMessage.request(id: 3, method: "ping"))
		let (_, pingResponse) = try await postSession.data(for: pingRequest)
		#expect((pingResponse as! HTTPURLResponse).statusCode == 202)

		let pingDelivered = await waitForCondition {
			responseEvent(capture.events.value, id: 3) != nil
		}
		#expect(pingDelivered)

		capture.task.cancel()
		#endif
	}

	@Test("Legacy SSE: unknown messages session returns 404")
	func legacySSEUnknownSessionRejected() async throws {
		let (transport, baseURL) = try await startTransport()
		defer { Task { try? await transport.stop() } }

		let session = URLSession(configuration: .ephemeral)
		let url = baseURL
			.appendingPathComponent("messages")
			.appendingPathComponent(UUID().uuidString)

		var request = URLRequest(url: url)
		request.httpMethod = "POST"
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.httpBody = try encode(JSONRPCMessage.request(id: 1, method: "ping"))

		let (_, response) = try await session.data(for: request)
		#expect((response as! HTTPURLResponse).statusCode == 404)
	}

	// MARK: - DELETE /mcp

	@Test("DELETE /mcp: removes session")
	func deleteSession() async throws {
		let (transport, baseURL) = try await startTransport()
		defer { Task { try? await transport.stop() } }

		let (sessionID, _) = try await initializeSession(url: baseURL.appendingPathComponent("mcp"))
		let session = URLSession(configuration: .ephemeral)

		var deleteReq = URLRequest(url: baseURL.appendingPathComponent("mcp"))
		deleteReq.httpMethod = "DELETE"
		deleteReq.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id")

		let (_, deleteResp) = try await session.data(for: deleteReq)
		#expect((deleteResp as! HTTPURLResponse).statusCode == 204)
	}

	@Test("DELETE /mcp: unknown session returns 404")
	func deleteUnknownSession() async throws {
		let (transport, baseURL) = try await startTransport()
		defer { Task { try? await transport.stop() } }

		let session = URLSession(configuration: .ephemeral)
		var request = URLRequest(url: baseURL.appendingPathComponent("mcp"))
		request.httpMethod = "DELETE"
		request.setValue(UUID().uuidString, forHTTPHeaderField: "Mcp-Session-Id")

		let (_, response) = try await session.data(for: request)
		#expect((response as! HTTPURLResponse).statusCode == 404)
	}

	@Test("Resumable request streams expire after the retention interval")
	func expiredRequestStreamResume() async throws {
		#if canImport(FoundationNetworking)
		return
		#else
		let (transport, baseURL) = try await startTransport(server: ResumableServer(), retentionInterval: 0.2)
		defer { Task { try? await transport.stop() } }

		let url = baseURL.appendingPathComponent("mcp")
		let (sessionID, _) = try await initializeSession(url: url)

		let capture = openStreamingRequest(
			try streamablePOSTRequest(
				url: url,
				message: .request(
					id: 9,
					method: "tools/call",
					params: [
						"name": .string("slowPing"),
						"arguments": .object([:]),
						"_meta": .object([
							"progressToken": .string("expiring-request")
						])
					]
				),
				sessionID: sessionID
			)
		)

		let sawProgress = await waitForCondition {
			notificationEvent(capture.events.value, method: "notifications/progress") != nil
		}
		#expect(sawProgress)
		let lastEventID = try #require(capture.events.value.last?.id)
		capture.task.cancel()

		try? await Task.sleep(nanoseconds: 700_000_000)

		let session = URLSession(configuration: .ephemeral)
		let (_, response) = try await session.data(for: generalSSERequest(url: url, sessionID: sessionID, lastEventID: lastEventID))
		#expect((response as! HTTPURLResponse).statusCode == 404)
		#endif
	}

	// MARK: - Uploads

	@Test("POST /mcp/uploads/:cid: unknown session returns 404")
	func uploadUnknownSessionRejected() async throws {
		let (transport, baseURL) = try await startTransport(server: UploadCapableServer())
		defer { Task { try? await transport.stop() } }

		let session = URLSession(configuration: .ephemeral)
		let url = baseURL
			.appendingPathComponent("mcp")
			.appendingPathComponent("uploads")
			.appendingPathComponent("cid-123")

		var request = URLRequest(url: url)
		request.httpMethod = "POST"
		request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
		request.setValue(UUID().uuidString, forHTTPHeaderField: "Mcp-Session-Id")
		request.httpBody = Data("hello".utf8)

		let (_, response) = try await session.data(for: request)
		#expect((response as! HTTPURLResponse).statusCode == 404)
	}

	// MARK: - CORS / OpenAPI / Error cases

	@Test("OPTIONS returns CORS headers")
	func corsHeaders() async throws {
		let (transport, baseURL) = try await startTransport()
		defer { Task { try? await transport.stop() } }

		let session = URLSession(configuration: .ephemeral)
		var request = URLRequest(url: baseURL.appendingPathComponent("mcp"))
		request.httpMethod = "OPTIONS"

		let (_, response) = try await session.data(for: request)
		let http = response as! HTTPURLResponse
		#expect(http.statusCode == 200)
		#expect(http.value(forHTTPHeaderField: "Access-Control-Allow-Methods")?.contains("POST") == true)
		#expect(http.value(forHTTPHeaderField: "Access-Control-Allow-Headers")?.contains("Content-Type") == true)
		#expect(http.value(forHTTPHeaderField: "Access-Control-Allow-Headers")?.contains("Mcp-Session-Id") == true)
	}

	@Test("GET /.well-known/ai-plugin.json returns manifest when serveOpenAPI is true")
	func aiPluginManifest() async throws {
		let server = Calculator()
		let transport = HTTPSSETransport(server: server, host: "127.0.0.1", port: 0)
		transport.serveOpenAPI = true
		try await transport.start()
		defer { Task { try? await transport.stop() } }

		let session = URLSession(configuration: .ephemeral)
		let url = URL(string: "http://127.0.0.1:\(transport.port)/.well-known/ai-plugin.json")!

		let (data, response) = try await session.data(from: url)
		let http = response as! HTTPURLResponse
		#expect(http.statusCode == 200)

		let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
		#expect(json["name_for_model"] as? String == "calculator")
		let api = json["api"] as? [String: Any]
		#expect((api?["url"] as? String)?.hasSuffix("/openapi.json") == true)
	}

	@Test("GET /.well-known/ai-plugin.json returns 404 when serveOpenAPI is false")
	func aiPluginManifestDisabled() async throws {
		let (transport, baseURL) = try await startTransport()
		defer { Task { try? await transport.stop() } }

		let session = URLSession(configuration: .ephemeral)
		let url = URL(string: "\(baseURL.absoluteString)/.well-known/ai-plugin.json")!

		let (_, response) = try await session.data(from: url)
		#expect((response as! HTTPURLResponse).statusCode == 404)
	}

	@Test("GET /openapi.json returns spec with tool paths")
	func openAPISpec() async throws {
		let server = Calculator()
		let transport = HTTPSSETransport(server: server, host: "127.0.0.1", port: 0)
		transport.serveOpenAPI = true
		try await transport.start()
		defer { Task { try? await transport.stop() } }

		let session = URLSession(configuration: .ephemeral)
		let url = URL(string: "http://127.0.0.1:\(transport.port)/openapi.json")!

		let (data, response) = try await session.data(from: url)
		let http = response as! HTTPURLResponse
		#expect(http.statusCode == 200)

		let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
		#expect(json["openapi"] as? String == "3.1.0")
		let info = json["info"] as? [String: Any]
		#expect(info?["title"] as? String == "Calculator")
		let paths = json["paths"] as? [String: Any]
		#expect(paths?["/calculator/add"] != nil)
	}

	@Test("POST /{serverName}/{toolName} calls tool and returns result")
	func openAPIToolCall() async throws {
		let server = Calculator()
		let transport = HTTPSSETransport(server: server, host: "127.0.0.1", port: 0)
		transport.serveOpenAPI = true
		try await transport.start()
		defer { Task { try? await transport.stop() } }

		let session = URLSession(configuration: .ephemeral)
		let url = URL(string: "http://127.0.0.1:\(transport.port)/calculator/add")!

		var request = URLRequest(url: url)
		request.httpMethod = "POST"
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.httpBody = try JSONSerialization.data(withJSONObject: ["a": 3, "b": 7])

		let (data, response) = try await session.data(for: request)
		let http = response as! HTTPURLResponse
		#expect(http.statusCode == 200)
		let body = String(data: data, encoding: .utf8) ?? ""
		#expect(body.contains("10"))
	}

	@Test("POST /mcp: missing body returns 400")
	func missingBody() async throws {
		let (transport, baseURL) = try await startTransport()
		defer { Task { try? await transport.stop() } }

		let session = URLSession(configuration: .ephemeral)
		var request = URLRequest(url: baseURL.appendingPathComponent("mcp"))
		request.httpMethod = "POST"
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")

		let (_, response) = try await session.data(for: request)
		#expect((response as! HTTPURLResponse).statusCode == 400)
	}

	@Test("GET /sse: wrong Accept header returns 400")
	func wrongAcceptHeader() async throws {
		let (transport, baseURL) = try await startTransport()
		defer { Task { try? await transport.stop() } }

		let session = URLSession(configuration: .ephemeral)
		var request = URLRequest(url: baseURL.appendingPathComponent("sse"))
		request.setValue("application/json", forHTTPHeaderField: "Accept")

		let (_, response) = try await session.data(for: request)
		#expect((response as! HTTPURLResponse).statusCode == 400)
	}

	@Test("POST /mcp: invalid protocol header returns 400")
	func invalidProtocolVersionHeader() async throws {
		let (transport, baseURL) = try await startTransport()
		defer { Task { try? await transport.stop() } }

		let session = URLSession(configuration: .ephemeral)
		let request = try streamablePOSTRequest(
			url: baseURL.appendingPathComponent("mcp"),
			message: initializeRequest(),
			protocolVersion: "bogus"
		)
		let (_, response) = try await session.data(for: request)
		#expect((response as! HTTPURLResponse).statusCode == 400)
	}

	@Test("unknown path returns 404")
	func unknownPath() async throws {
		let (transport, baseURL) = try await startTransport()
		defer { Task { try? await transport.stop() } }

		let session = URLSession(configuration: .ephemeral)
		let (_, response) = try await session.data(from: baseURL.appendingPathComponent("nonexistent"))
		#expect((response as! HTTPURLResponse).statusCode == 404)
	}
}

private struct StreamCapture {
	let response: Box<HTTPURLResponse?>
	let events: Box<[SSEClientMessage]>
	let task: Task<Void, Error>
}

/// Thread-safe box for capturing values from @Sendable closures.
private final class Box<T: Sendable>: @unchecked Sendable {
	var value: T
	init(_ value: T) { self.value = value }
}
