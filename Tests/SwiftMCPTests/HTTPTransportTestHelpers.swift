// Shared HTTP transport test helpers.

import Testing
import SwiftCross
@testable import SwiftMCP

@MCPServer(name: "ResumableServer")
final class ResumableServer {
    @MCPTool(description: "Emits progress before returning pong")
    func slowPing() async -> String {
        await RequestContext.current?.reportProgress(0.2, total: 1.0, message: "starting")
        try? await Task.sleep(nanoseconds: 150_000_000)
        await RequestContext.current?.reportProgress(0.6, total: 1.0, message: "middle")
        try? await Task.sleep(nanoseconds: 150_000_000)
        return "pong"
    }
}

struct HTTPTransportStreamCapture {
    let response: HTTPTransportBox<HTTPURLResponse?>
    let events: HTTPTransportBox<[SSEClientMessage]>
    let task: Task<Void, Error>
}

/// Thread-safe box for capturing values from @Sendable closures.
final class HTTPTransportBox<T: Sendable>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

enum HTTPTransportTestHelpers {

    static func startTransport(
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

    static func encode(_ message: JSONRPCMessage) throws -> Data {
        try JSONEncoder().encode(message)
    }

    static func decode(_ data: Data) throws -> JSONRPCMessage {
        try JSONDecoder().decode(JSONRPCMessage.self, from: data)
    }

    static func initializeRequest(id: Int = 1) -> JSONRPCMessage {
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

    static func streamablePOSTRequest(
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

    static func generalSSERequest(
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

    static func readFiniteSSEResponse(_ request: URLRequest) async throws -> (HTTPURLResponse, [SSEClientMessage]) {
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

    static func openStreamingRequest(_ request: URLRequest) -> HTTPTransportStreamCapture {
        let responseBox = HTTPTransportBox<HTTPURLResponse?>(nil)
        let eventsBox = HTTPTransportBox<[SSEClientMessage]>([])

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

        return HTTPTransportStreamCapture(response: responseBox, events: eventsBox, task: task)
    }

    static func waitForCondition(
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

    static func initializeSession(url: URL) async throws -> (String, [SSEClientMessage]) {
        let request = try streamablePOSTRequest(url: url, message: initializeRequest())
        let (response, events) = try await readFiniteSSEResponse(request)
        guard let sessionID = response.value(forHTTPHeaderField: "Mcp-Session-Id") else {
            throw TestError("Expected Mcp-Session-Id header")
        }
        return (sessionID, events)
    }

    static func decodeEventMessage(_ event: SSEClientMessage) throws -> JSONRPCMessage? {
        guard !event.data.isEmpty else {
            return nil
        }
        return try decode(Data(event.data.utf8))
    }

    static func responseEvent(_ events: [SSEClientMessage], id: Int) -> SSEClientMessage? {
        events.first { event in
            guard let message = try? decodeEventMessage(event),
                  case .response(let response) = message else {
                return false
            }
            return response.id == .int(id)
        }
    }

    static func notificationEvent(_ events: [SSEClientMessage], method: String) -> SSEClientMessage? {
        events.first { event in
            guard let message = try? decodeEventMessage(event),
                  case .notification(let notification) = message else {
                return false
            }
            return notification.method == method
        }
    }

    static func errorResponseEvent(_ events: [SSEClientMessage], id: Int) -> SSEClientMessage? {
        events.first { event in
            guard let message = try? decodeEventMessage(event),
                  case .errorResponse(let errorResponse) = message else {
                return false
            }
            return errorResponse.id == .int(id)
        }
    }
}
