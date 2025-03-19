import Foundation
import Testing
@testable import SwiftMCP
import NIOCore
import NIOHTTP1
import AnyCodable

/// Helper class to manage SSE message reading
actor SSEReader {
    private var buffer = ""
    private let stream: URLSession.AsyncBytes
    private var continuation: CheckedContinuation<SSEMessage, Error>?
    private var timeoutTask: Task<Void, Never>?
    
    init(stream: URLSession.AsyncBytes) {
        self.stream = stream
    }
    
    /// Await the next SSE message with a timeout
    /// - Parameter timeout: Timeout in seconds (default: 5)
    /// - Returns: The next SSE message
    func nextMessage(timeout: TimeInterval = 5) async throws -> SSEMessage {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            
            // Set up timeout
            self.timeoutTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                await self.handleTimeout()
            }
            
            // Start reading if not already reading
            if self.timeoutTask?.isCancelled == false {
                Task {
                    await self.readMessages()
                }
            }
        }
    }
    
    private func handleTimeout() async {
        if let continuation = self.continuation {
            self.continuation = nil
            self.timeoutTask = nil
            continuation.resume(throwing: NSError(domain: "SSETest", 
                                               code: -1, 
                                               userInfo: [NSLocalizedDescriptionKey: "Timeout waiting for SSE message"]))
        }
    }
    
    private func readMessages() async {
        do {
            for try await line in stream.lines {
                buffer += line + "\n"
                
                if let message = SSEMessage(buffer) {
                    buffer = ""
                    if let continuation = self.continuation {
                        self.continuation = nil
                        self.timeoutTask?.cancel()
                        self.timeoutTask = nil
                        continuation.resume(returning: message)
                        return
                    }
                }
            }
        } catch {
            continuation?.resume(throwing: error)
            continuation = nil
            timeoutTask?.cancel()
            timeoutTask = nil
        }
    }
}

@Test
func testHTTPSSETransport() async throws {
    // Create a calculator server
    let calculator = Calculator()
    let port = 8091  // Use a different port than the demo to avoid conflicts
    
    // Create and start the transport in the background
    let transport = HTTPSSETransport(server: calculator, port: port)
    transport.serveOpenAPI = true  // Enable OpenAPI endpoints
    
    // Start the server
    try await transport.start()
    
    // Test 1: Connect to SSE endpoint and make JSONRPC requests
    let url = URL(string: "http://localhost:\(port)/sse")!
    var request = URLRequest(url: url)
    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
    
    let (stream, _) = try await URLSession.shared.bytes(for: request)
    let reader = SSEReader(stream: stream)
    
    // Wait for client ID message
    let initialMessage = try await reader.nextMessage()
    guard let endpointURL = URL(string: initialMessage.data), endpointURL.path.contains("/messages/") else {
        throw NSError(domain: "SSETest", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid client ID message"])
    }
    let clientId = endpointURL.lastPathComponent
    #expect(clientId.isEmpty == false, "Should receive a valid client ID")
    
    // Test 2: Make a JSONRPC request
    var jsonrpcRequest = URLRequest(url: endpointURL)
    jsonrpcRequest.httpMethod = "POST"
    jsonrpcRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    
    let toolRequest = JSONRPCMessage(
        id: 1,
        method: "tools/call",
        params: [
            "name": AnyCodable("add"),
            "arguments": AnyCodable([
                "a": 2,
                "b": 3
            ])
        ]
    )
    
    let encoder = JSONEncoder()
    jsonrpcRequest.httpBody = try encoder.encode(toolRequest)
    
    // Send request and wait for response via SSE
    let (data, response) = try await URLSession.shared.data(for: jsonrpcRequest)
    #expect(data.isEmpty)
    
    let httpResponse = unwrap(response as? HTTPURLResponse)
    #expect(httpResponse.statusCode == 202)
    
    // Wait for SSE response
    let responseMessage = try await reader.nextMessage()
    let jsonData = responseMessage.data.data(using: .utf8)!
    let jsonResponse = try JSONDecoder().decode(JSONRPCMessage.self, from: jsonData)
    
    // Verify response structure
    #expect(jsonResponse.id == 1)
    #expect(jsonResponse.error == nil)
    #expect(jsonResponse.method == nil)
    #expect(jsonResponse.params == nil)
    
    // Verify result dictionary
    let result = unwrap(jsonResponse.result)
    
    // Check isError is false
    let isError = unwrap(result["isError"]?.value as? Bool)
    #expect(isError == false)
    
    // Check content structure
    let content = unwrap(result["content"]?.value as? [[String: String]])
    let firstContent = unwrap(content.first)
    let type = unwrap(firstContent["type"])
    let text = unwrap(firstContent["text"])
    
    #expect(type == "text")
    #expect(text == "5")  // 2 + 3 = 5
    
    // Test 3: Check OpenAPI endpoints
    let openAPIURL = URL(string: "http://localhost:\(port)/openapi.json")!
    let (openAPIData, openAPIResponse) = try await URLSession.shared.data(from: openAPIURL)
    let openAPIHTTPResponse = unwrap(openAPIResponse as? HTTPURLResponse)
    #expect(openAPIHTTPResponse.statusCode == 200)
    
    // Decode OpenAPI spec
    let decoder = JSONDecoder()
    let openAPISpec = try decoder.decode(OpenAPISpec.self, from: openAPIData)
    
    // Verify OpenAPI spec
    #expect(openAPISpec.openapi.hasPrefix("3."))  // Should be OpenAPI 3.x
    #expect(openAPISpec.info.title == calculator.serverName)
    #expect(openAPISpec.paths.isEmpty == false)
    
    // Clean up
    try await transport.stop()
}
