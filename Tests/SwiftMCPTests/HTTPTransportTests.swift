import Testing
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import SwiftMCP


@Suite("HTTP Transport Integration")
struct HTTPTransportTests {

	/// Create a transport, start it, and return the base URL.
	private func startTransport() async throws -> (HTTPSSETransport, URL) {
		let server = Calculator()
		let transport = HTTPSSETransport(server: server, host: "127.0.0.1", port: 0)
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
				"protocolVersion": .string("2025-06-18"),
				"capabilities": .object([:]),
				"clientInfo": .object([
					"name": .string("TestClient"),
					"version": .string("1.0")
				])
			]
		)
	}

	// MARK: - Modern Streamable HTTP (POST /mcp)

	@Test("POST /mcp: initialize without SSE returns immediate response")
	func modernInitialize() async throws {
		let (transport, baseURL) = try await startTransport()
		defer { Task { try? await transport.stop() } }

		let session = URLSession(configuration: .ephemeral)
		var request = URLRequest(url: baseURL.appendingPathComponent("mcp"))
		request.httpMethod = "POST"
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.setValue("application/json", forHTTPHeaderField: "Accept")
		request.httpBody = try encode(initializeRequest())

		let (data, httpResponse) = try await session.data(for: request)
		let response = httpResponse as! HTTPURLResponse

		#expect(response.statusCode == 200)
		#expect(response.value(forHTTPHeaderField: "Mcp-Session-Id") != nil)

		let message = try decode(data)
		guard case .response(let resp) = message else {
			Issue.record("Expected response, got \(message)")
			return
		}
		#expect(resp.id == .int(1))

		guard let result = resp.result,
			  let protocolVersion = result["protocolVersion"]?.value as? String else {
			Issue.record("Missing protocolVersion in result")
			return
		}
		#expect(protocolVersion == "2025-06-18")
	}

	@Test("POST /mcp: ping returns pong")
	func modernPing() async throws {
		let (transport, baseURL) = try await startTransport()
		defer { Task { try? await transport.stop() } }

		let session = URLSession(configuration: .ephemeral)
		let url = baseURL.appendingPathComponent("mcp")

		// Initialize first
		var initReq = URLRequest(url: url)
		initReq.httpMethod = "POST"
		initReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
		initReq.setValue("application/json", forHTTPHeaderField: "Accept")
		initReq.httpBody = try encode(initializeRequest())

		let (_, initResp) = try await session.data(for: initReq)
		let sessionId = (initResp as! HTTPURLResponse).value(forHTTPHeaderField: "Mcp-Session-Id")!

		// Ping
		let pingMessage = JSONRPCMessage.request(id: 2, method: "ping")
		var pingReq = URLRequest(url: url)
		pingReq.httpMethod = "POST"
		pingReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
		pingReq.setValue("application/json", forHTTPHeaderField: "Accept")
		pingReq.setValue(sessionId, forHTTPHeaderField: "Mcp-Session-Id")
		pingReq.httpBody = try encode(pingMessage)

		let (pingData, pingResp) = try await session.data(for: pingReq)
		let pingHTTP = pingResp as! HTTPURLResponse
		#expect(pingHTTP.statusCode == 200)

		// Session ID must be preserved across requests
		let pingSessionId = pingHTTP.value(forHTTPHeaderField: "Mcp-Session-Id")
		#expect(pingSessionId == sessionId, "Session ID changed between requests")

		let message = try decode(pingData)
		guard case .response(let resp) = message else {
			Issue.record("Expected response, got \(message)")
			return
		}
		#expect(resp.id == .int(2))
		#expect(resp.result != nil) // empty object = pong
	}

	@Test("POST /mcp: session ID is preserved across requests")
	func sessionIdPreserved() async throws {
		let (transport, baseURL) = try await startTransport()
		defer { Task { try? await transport.stop() } }

		let session = URLSession(configuration: .ephemeral)
		let url = baseURL.appendingPathComponent("mcp")

		// Request 1: Initialize
		var req1 = URLRequest(url: url)
		req1.httpMethod = "POST"
		req1.setValue("application/json", forHTTPHeaderField: "Content-Type")
		req1.setValue("application/json", forHTTPHeaderField: "Accept")
		req1.httpBody = try encode(initializeRequest())

		let (_, resp1) = try await session.data(for: req1)
		let sessionId = (resp1 as! HTTPURLResponse).value(forHTTPHeaderField: "Mcp-Session-Id")!
		#expect(UUID(uuidString: sessionId) != nil, "Session ID is not a valid UUID")

		// Request 2: Ping with same session ID
		var req2 = URLRequest(url: url)
		req2.httpMethod = "POST"
		req2.setValue("application/json", forHTTPHeaderField: "Content-Type")
		req2.setValue("application/json", forHTTPHeaderField: "Accept")
		req2.setValue(sessionId, forHTTPHeaderField: "Mcp-Session-Id")
		req2.httpBody = try encode(JSONRPCMessage.request(id: 2, method: "ping"))

		let (_, resp2) = try await session.data(for: req2)
		let sessionId2 = (resp2 as! HTTPURLResponse).value(forHTTPHeaderField: "Mcp-Session-Id")!
		#expect(sessionId2 == sessionId, "Session ID changed: \(sessionId) → \(sessionId2)")

		// Request 3: tools/list with same session ID
		var req3 = URLRequest(url: url)
		req3.httpMethod = "POST"
		req3.setValue("application/json", forHTTPHeaderField: "Content-Type")
		req3.setValue("application/json", forHTTPHeaderField: "Accept")
		req3.setValue(sessionId, forHTTPHeaderField: "Mcp-Session-Id")
		req3.httpBody = try encode(JSONRPCMessage.request(id: 3, method: "tools/list"))

		let (_, resp3) = try await session.data(for: req3)
		let sessionId3 = (resp3 as! HTTPURLResponse).value(forHTTPHeaderField: "Mcp-Session-Id")!
		#expect(sessionId3 == sessionId, "Session ID changed: \(sessionId) → \(sessionId3)")
	}

	@Test("POST /mcp: with active SSE returns 202 and streams response")
	func modernSSEStreaming() async throws {
		#if canImport(FoundationNetworking)
		// URLSession.bytes(for:) is unavailable on Linux FoundationNetworking.
		return
		#else
		let (transport, baseURL) = try await startTransport()
		defer { Task { try? await transport.stop() } }

		let url = baseURL.appendingPathComponent("mcp")
		let postSession = URLSession(configuration: .ephemeral)

		// Step 1: Initialize WITHOUT SSE to get a session ID (immediate 200 response)
		var initReq = URLRequest(url: url)
		initReq.httpMethod = "POST"
		initReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
		initReq.setValue("application/json", forHTTPHeaderField: "Accept")
		initReq.httpBody = try encode(initializeRequest())

		let (_, initResp) = try await postSession.data(for: initReq)
		let sessionId = (initResp as! HTTPURLResponse).value(forHTTPHeaderField: "Mcp-Session-Id")!
		#expect((initResp as! HTTPURLResponse).statusCode == 200)

		// Step 2: Open SSE connection in background Task
		// bytes(for:) blocks until first body bytes arrive.
		let receivedEvents = Box<[SSEClientMessage]>([])
		var sseReq = URLRequest(url: url)
		sseReq.setValue("text/event-stream", forHTTPHeaderField: "Accept")
		sseReq.setValue(sessionId, forHTTPHeaderField: "Mcp-Session-Id")

		let sseTask = Task {
			let session = URLSession(configuration: .ephemeral)
			let (sseBytes, _) = try await session.bytes(for: sseReq)
			for try await message in sseBytes.lines.sseMessages() {
				receivedEvents.value.append(message)
			}
		}

		// Wait for SSE channel registration
		try await Task.sleep(for: .milliseconds(300))

		// Step 3: List tools via POST — should get 202, response via SSE
		let toolsMessage = JSONRPCMessage.request(id: 2, method: "tools/list")
		var toolsReq = URLRequest(url: url)
		toolsReq.httpMethod = "POST"
		toolsReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
		toolsReq.setValue("application/json", forHTTPHeaderField: "Accept")
		toolsReq.setValue(sessionId, forHTTPHeaderField: "Mcp-Session-Id")
		toolsReq.httpBody = try encode(toolsMessage)

		let (_, toolsResp) = try await postSession.data(for: toolsReq)
		let toolsHTTP = toolsResp as! HTTPURLResponse
		#expect(toolsHTTP.statusCode == 202)
		#expect(toolsHTTP.value(forHTTPHeaderField: "Mcp-Session-Id") == sessionId, "Session ID changed on tools/list")

		try await Task.sleep(for: .milliseconds(500))

		// Step 4: Ping via POST — should get 202
		let pingMessage = JSONRPCMessage.request(id: 3, method: "ping")
		var pingReq = URLRequest(url: url)
		pingReq.httpMethod = "POST"
		pingReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
		pingReq.setValue("application/json", forHTTPHeaderField: "Accept")
		pingReq.setValue(sessionId, forHTTPHeaderField: "Mcp-Session-Id")
		pingReq.httpBody = try encode(pingMessage)

		let (_, pingResp) = try await postSession.data(for: pingReq)
		#expect((pingResp as! HTTPURLResponse).statusCode == 202)

		try await Task.sleep(for: .milliseconds(500))

		sseTask.cancel()

		// Verify tools/list response arrived via SSE
		let toolsEvent = receivedEvents.value.first { event in
			guard let msg = try? decode(Data(event.data.utf8)),
				  case .response(let r) = msg, r.id == .int(2) else { return false }
			return true
		}
		#expect(toolsEvent != nil, "Expected tools/list response via SSE")

		if let event = toolsEvent {
			let message = try decode(Data(event.data.utf8))
			guard case .response(let resp) = message,
				  let result = resp.result,
				  let tools = result["tools"] else {
				Issue.record("Expected tools in response")
				return
			}
			// Calculator has tools (add, subtract, etc.)
			guard case .array(let toolArray) = tools else {
				Issue.record("Expected tools array")
				return
			}
			#expect(!toolArray.isEmpty, "Calculator should have tools")
		}

		// Verify ping response arrived via SSE
		let pingEvent = receivedEvents.value.first { event in
			guard let msg = try? decode(Data(event.data.utf8)),
				  case .response(let r) = msg, r.id == .int(3) else { return false }
			return true
		}
		#expect(pingEvent != nil, "Expected ping response via SSE")
		#endif
	}

	// MARK: - Legacy SSE Protocol (GET /sse + POST /messages)

	@Test("Legacy SSE: connect, get endpoint, initialize, ping")
	func legacySSEFullFlow() async throws {
		#if canImport(FoundationNetworking)
		// URLSession.bytes(for:) is unavailable on Linux FoundationNetworking.
		return
		#else
		let (transport, baseURL) = try await startTransport()
		defer { Task { try? await transport.stop() } }

		let receivedEvents = Box<[SSEClientMessage]>([])

		// bytes(for:) blocks until first body bytes arrive,
		// so the SSE connection must be opened in a background Task.
		var sseReq = URLRequest(url: baseURL.appendingPathComponent("sse"))
		sseReq.setValue("text/event-stream", forHTTPHeaderField: "Accept")

		let sseTask = Task {
			let session = URLSession(configuration: .ephemeral)
			let (sseBytes, _) = try await session.bytes(for: sseReq)
			for try await message in sseBytes.lines.sseMessages() {
				receivedEvents.value.append(message)
			}
		}

		// Wait for endpoint event (legacy SSE sends it immediately)
		try await Task.sleep(for: .milliseconds(500))

		let endpointEvent = receivedEvents.value.first { $0.event == "endpoint" }
		guard let endpointData = endpointEvent?.data,
			  let messagesURL = URL(string: endpointData) else {
			sseTask.cancel()
			Issue.record("Never received endpoint event. Events: \(receivedEvents.value.map { "[\($0.event)] \($0.data)" })")
			return
		}

		#expect(messagesURL.path.hasPrefix("/messages/"))

		// Extract the session ID from the endpoint URL — must be a valid UUID
		let legacySessionId = messagesURL.lastPathComponent
		#expect(UUID(uuidString: legacySessionId) != nil, "Endpoint session ID is not a valid UUID: \(legacySessionId)")

		// Initialize via POST to the messages endpoint
		let postSession = URLSession(configuration: .ephemeral)
		var initReq = URLRequest(url: messagesURL)
		initReq.httpMethod = "POST"
		initReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
		initReq.httpBody = try encode(initializeRequest())

		let (_, initResp) = try await postSession.data(for: initReq)
		#expect((initResp as! HTTPURLResponse).statusCode == 202)

		// Wait for SSE to deliver the initialize response.
		// Ignore later notifications like ping; explicitly look for the response with id 1.
		let deadline = Date().addingTimeInterval(2)
		var initResponse: JSONRPCMessage.JSONRPCResponseData?
		while Date() < deadline, initResponse == nil {
			for event in receivedEvents.value where event.event != "endpoint" {
				let message = try decode(Data(event.data.utf8))
				if case .response(let resp) = message, resp.id == .int(1) {
					initResponse = resp
					break
				}
			}
			if initResponse == nil {
				try await Task.sleep(for: .milliseconds(100))
			}
		}

		guard let initResponse else {
			Issue.record("Expected initialize response via SSE. All events: \(receivedEvents.value.map { "[\($0.event)] \($0.data.prefix(80))" })")
			sseTask.cancel()
			return
		}
		#expect(initResponse.id == .int(1))

		// Send initialized notification
		let initializedNotification = JSONRPCMessage.notification(method: "notifications/initialized")
		var notifReq = URLRequest(url: messagesURL)
		notifReq.httpMethod = "POST"
		notifReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
		notifReq.httpBody = try encode(initializedNotification)

		let (_, notifResp) = try await postSession.data(for: notifReq)
		#expect((notifResp as! HTTPURLResponse).statusCode == 202)

		// List tools
		let toolsMessage = JSONRPCMessage.request(id: 2, method: "tools/list")
		var toolsReq = URLRequest(url: messagesURL)
		toolsReq.httpMethod = "POST"
		toolsReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
		toolsReq.httpBody = try encode(toolsMessage)

		let (_, toolsResp) = try await postSession.data(for: toolsReq)
		#expect((toolsResp as! HTTPURLResponse).statusCode == 202)

		try await Task.sleep(for: .milliseconds(500))

		// Ping
		let pingMessage = JSONRPCMessage.request(id: 3, method: "ping")
		var pingReq = URLRequest(url: messagesURL)
		pingReq.httpMethod = "POST"
		pingReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
		pingReq.httpBody = try encode(pingMessage)

		let (_, pingResp) = try await postSession.data(for: pingReq)
		#expect((pingResp as! HTTPURLResponse).statusCode == 202)

		try await Task.sleep(for: .milliseconds(500))

		sseTask.cancel()

		// Verify tools/list response
		let allDataEvents = receivedEvents.value.filter { $0.event != "endpoint" }
		let toolsEvent = allDataEvents.first { event in
			guard let msg = try? decode(Data(event.data.utf8)),
				  case .response(let r) = msg, r.id == .int(2) else { return false }
			return true
		}
		#expect(toolsEvent != nil, "Expected tools/list response via SSE")

		if let event = toolsEvent {
			let message = try decode(Data(event.data.utf8))
			guard case .response(let resp) = message,
				  let result = resp.result,
				  let tools = result["tools"] else {
				Issue.record("Expected tools in response")
				return
			}
			guard case .array(let toolArray) = tools else {
				Issue.record("Expected tools array")
				return
			}
			#expect(!toolArray.isEmpty, "Calculator should have tools")
		}

		// Verify ping response
		let pingEvent = allDataEvents.first { event in
			guard let msg = try? decode(Data(event.data.utf8)),
				  case .response(let r) = msg, r.id == .int(3) else { return false }
			return true
		}
		#expect(pingEvent != nil, "Expected ping response via SSE")
		#endif
	}

	// MARK: - DELETE /mcp

	@Test("DELETE /mcp: removes session")
	func deleteSession() async throws {
		let (transport, baseURL) = try await startTransport()
		defer { Task { try? await transport.stop() } }

		let session = URLSession(configuration: .ephemeral)
		let url = baseURL.appendingPathComponent("mcp")

		// Initialize to create a session
		var initReq = URLRequest(url: url)
		initReq.httpMethod = "POST"
		initReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
		initReq.setValue("application/json", forHTTPHeaderField: "Accept")
		initReq.httpBody = try encode(initializeRequest())

		let (_, initResp) = try await session.data(for: initReq)
		let sessionId = (initResp as! HTTPURLResponse).value(forHTTPHeaderField: "Mcp-Session-Id")!

		// DELETE /mcp to remove the session
		var deleteReq = URLRequest(url: url)
		deleteReq.httpMethod = "DELETE"
		deleteReq.setValue(sessionId, forHTTPHeaderField: "Mcp-Session-Id")

		let (_, deleteResp) = try await session.data(for: deleteReq)
		#expect((deleteResp as! HTTPURLResponse).statusCode == 204)
	}

	// MARK: - CORS

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

	// MARK: - OpenAPI

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

		// Should have paths for Calculator tools
		let paths = json["paths"] as? [String: Any]
		#expect(paths?["/calculator/add"] != nil, "Expected /calculator/add path")
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

		// The result should contain 10 (3 + 7)
		let body = String(data: data, encoding: .utf8) ?? ""
		#expect(body.contains("10"), "Expected result to contain 10, got: \(body)")
	}

	// MARK: - Error cases

	@Test("POST /mcp: missing body returns 400")
	func missingBody() async throws {
		let (transport, baseURL) = try await startTransport()
		defer { Task { try? await transport.stop() } }

		let session = URLSession(configuration: .ephemeral)
		var request = URLRequest(url: baseURL.appendingPathComponent("mcp"))
		request.httpMethod = "POST"
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.setValue("application/json", forHTTPHeaderField: "Accept")
		// No body

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

	@Test("unknown path returns 404")
	func unknownPath() async throws {
		let (transport, baseURL) = try await startTransport()
		defer { Task { try? await transport.stop() } }

		let session = URLSession(configuration: .ephemeral)
		let (_, response) = try await session.data(from: baseURL.appendingPathComponent("nonexistent"))
		#expect((response as! HTTPURLResponse).statusCode == 404)
	}
}


/// Thread-safe box for capturing values from @Sendable closures.
private final class Box<T: Sendable>: @unchecked Sendable {
	var value: T
	init(_ value: T) { self.value = value }
}
