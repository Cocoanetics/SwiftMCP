import Foundation
import AnyCodable
@testable import SwiftMCP
import Logging

// Configure logging to use stdout
private let logger = Logger(label: "com.cocoanetics.SwiftMCP.MCPClient") { label in
    StreamLogHandler.standardOutput(label: label)
}

/// A client for communicating with an MCP server over HTTP+SSE
public actor MCPClient {
    private var stream: URLSession.AsyncBytes?
    private var messagesURL: URL?
    private var messageStream: AsyncStream<SSEMessage>?
    private var streamTask: Task<Void, Never>?
    private let endpointURL: URL
    
    /// Initialize a new MCP client with the SSE endpoint URL
    /// - Parameter endpointURL: The URL of the SSE endpoint (e.g. http://localhost:8080/sse)
    public init(endpointURL: URL) {
        self.endpointURL = endpointURL
        logger.info("Initialized MCPClient with endpoint: \(endpointURL)")
    }
    
    /// Connect to the SSE endpoint and establish a connection
    /// - Throws: An error if the connection fails
    public func connect() async throws {
        logger.info("Connecting to SSE endpoint: \(endpointURL)")
        var request = URLRequest(url: endpointURL)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        
        let (stream, response) = try await URLSession.shared.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MCPError.invalidResponse
        }
        logger.info("Connected to SSE endpoint, status: \(httpResponse.statusCode)")
        self.stream = stream
        
        // Create a single message stream for all messages
        let (messageStream, continuation) = AsyncStream.makeStream(of: SSEMessage.self)
        self.messageStream = messageStream
        
        // Start a single task to read messages
        streamTask = Task {
            await readMessages(continuation: continuation)
        }
        
        // Wait for the initial message containing the messages endpoint URL
        logger.info("Waiting for initial message with endpoint URL")
        let initialMessage = try await nextMessage(timeout: 5)
        logger.info("Received initial message: \(initialMessage.data)")
        
        guard let messagesURL = URL(string: initialMessage.data),
              messagesURL.path.contains("/messages/") else {
            logger.error("Invalid messages endpoint URL: \(initialMessage.data)")
            throw MCPError.invalidEndpointURL
        }
        self.messagesURL = messagesURL
        logger.info("Successfully connected with messages URL: \(messagesURL)")
    }
    
    deinit {
        streamTask?.cancel()
    }
    
    /// Send a JSONRPC message and wait for the response
    /// - Parameters:
    ///   - message: The JSONRPC message to send
    ///   - timeout: Timeout in seconds (default: 5)
    /// - Returns: The JSONRPC response
    /// - Throws: An error if the request fails or times out
    public func send(_ message: JSONRPCMessage, timeout: TimeInterval = 5) async throws -> JSONRPCMessage {
        guard let messagesURL = messagesURL else {
            logger.error("Not connected to server")
            throw MCPError.notConnected
        }
        
        logger.info("Sending JSONRPC message to: \(messagesURL)")
        var request = URLRequest(url: messagesURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(message)
        
        // Send the request
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 202 else {
            logger.error("Invalid response from server")
            throw MCPError.invalidResponse
        }
        
        logger.info("Request accepted, waiting for SSE response")
        // Wait for the SSE response
        let responseMessage = try await nextMessage(timeout: timeout)
        logger.info("Received SSE response")
        
        let jsonData = responseMessage.data.data(using: .utf8)!
        return try JSONDecoder().decode(JSONRPCMessage.self, from: jsonData)
    }
    
    /// Get the next SSE message with a timeout
    /// - Parameter timeout: Timeout in seconds (default: 5)
    /// - Returns: The next SSE message
    private func nextMessage(timeout: TimeInterval = 5) async throws -> SSEMessage {
        guard let messageStream = self.messageStream else {
            throw MCPError.notConnected
        }
        return try await nextMessage(from: messageStream, timeout: timeout)
    }
    
    /// Get the next SSE message from a specific stream with a timeout
    /// - Parameters:
    ///   - stream: The stream to read from
    ///   - timeout: Timeout in seconds
    /// - Returns: The next SSE message
    private func nextMessage(from stream: AsyncStream<SSEMessage>, timeout: TimeInterval) async throws -> SSEMessage {
        logger.info("Waiting for next message with timeout: \(timeout)s")
        return try await withThrowingTaskGroup(of: SSEMessage.self) { group in
            // Task to read the next message from the stream
            group.addTask {
                var iterator = stream.makeAsyncIterator()
                if let message = await iterator.next() {
                    return message
                }
                throw MCPError.invalidResponse
            }
            
            // Task to enforce a timeout
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw MCPError.timeout
            }
            
            // Return the first task that completes
            let message = try await group.next()!
            group.cancelAll()
            return message
        }
    }
    
    private func readMessages(continuation: AsyncStream<SSEMessage>.Continuation) async {
        guard let stream = stream else {
            logger.error("No stream available, finishing continuation")
            continuation.finish()
            return
        }
        
        do {
            var currentEvent: String?
            
            for try await line in stream.lines {
                logger.info("Received line: \(line)")
                
                if line.hasPrefix("data: ") {
                    // Handle data lines immediately
                    let data = String(line.dropFirst(6)) // Remove "data: " prefix
                    logger.info("Found data line: \(data)")
                    
                    // Format the complete SSE message
                    var messageText = ""
                    if let event = currentEvent {
                        messageText += "event: \(event)\n"
                    }
                    messageText += "data: \(data)\n"
                    
                    if let message = SSEMessage(messageText) {
                        logger.info("Successfully parsed SSE message with data: \(message.data)")
                        continuation.yield(message)
                    } else {
                        logger.error("Failed to parse SSE message: \(messageText)")
                    }
                    
                    // Reset for next message
                    currentEvent = nil
                } else if line.hasPrefix("event: ") {
                    // Handle event lines
                    let event = String(line.dropFirst(7)) // Remove "event: " prefix
                    currentEvent = event
                    logger.info("Found event line: \(event)")
                } else if !line.isEmpty {
                    // Skip non-empty lines that aren't SSE format
                    logger.info("Skipping line: \(line)")
                }
            }
        } catch {
            logger.error("Error reading stream: \(error)")
        }
        
        logger.info("Stream ended, finishing continuation")
        continuation.finish()
    }
}

/// Errors that can occur during MCP client operations
public enum MCPError: LocalizedError {
    case notConnected
    case invalidEndpointURL
    case invalidResponse
    case timeout
    
    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Client is not connected to the server"
        case .invalidEndpointURL:
            return "Invalid messages endpoint URL received from server"
        case .invalidResponse:
            return "Invalid response received from server"
        case .timeout:
            return "Request timed out"
        }
    }
}
