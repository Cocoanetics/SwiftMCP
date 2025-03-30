import Foundation
import ArgumentParser
import SwiftMCP
import Logging
#if canImport(OSLog)
import OSLog
#endif


/// A person's contact information
@Schema
struct ContactInfo {
	/// The person's full name
	let name: String
	
	/// The person's email address
	let email: String
	
	/// The person's phone number (optional)
	let phone: String?
	
	/// The person's age
	var age: Int = 0
	
	/// The person's address
	var addresses: [Address]?
}

/// A person's address
@Schema
struct Address {
	/// The street name
	let street: String
	
	/// The city name
	let city: String
}

/**
 A command that starts an HTTP server with Server-Sent Events (SSE) support for SwiftMCP.
 
 This mode provides a long-running HTTP server that supports:
 - Server-Sent Events (SSE) for real-time updates
 - JSON-RPC over HTTP POST for function calls
 - Optional bearer token authentication
 - Optional OpenAPI endpoints for AI plugin integration
 
 Key Features:
 1. Server-Sent Events:
    - Connect to `/sse` endpoint for real-time updates
    - Receive function call results and notifications
    - Maintain persistent connections with clients
 
 2. JSON-RPC Endpoints:
    - Send POST requests to `/<serverName>/<toolName>`
    - Standard JSON-RPC 2.0 request/response format
    - Support for batched requests
 
 3. Security:
    - Optional bearer token authentication
    - CORS support for web clients
    - Secure error handling and validation
 
 4. AI Plugin Support:
    - OpenAPI specification at `/openapi.json`
    - AI plugin manifest at `/.well-known/ai-plugin.json`
    - Compatible with AI plugin standards
 */
final class HTTPSSECommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "httpsse",
        abstract: "Start an HTTP server with Server-Sent Events (SSE) support",
        discussion: """
  Start an HTTP server that supports Server-Sent Events (SSE) and JSON-RPC.
  
  Features:
  - Server-Sent Events endpoint at /sse
  - JSON-RPC endpoints at /<serverName>/<toolName>
  - Optional bearer token authentication
  - Optional OpenAPI endpoints for AI plugin integration
  
  Examples:
    # Basic usage
    SwiftMCPDemo httpsse --port 8080
    
    # With authentication
    SwiftMCPDemo httpsse --port 8080 --token my-secret-token
    
    # With OpenAPI support
    SwiftMCPDemo httpsse --port 8080 --openapi
"""
    )
    
    @Option(name: .long, help: "The port to listen on")
    var port: Int
    
    @Option(name: .long, help: "Bearer token for authorization")
    var token: String?
    
    @Flag(name: .long, help: "Enable OpenAPI endpoints")
    var openapi: Bool = false
    
    // Make this a computed property instead of stored property
    private var signalHandler: SignalHandler? = nil
    
    required init() {}
    
    // Add manual Decodable conformance
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.port = try container.decode(Int.self, forKey: .port)
        self.token = try container.decodeIfPresent(String.self, forKey: .token)
        self.openapi = try container.decode(Bool.self, forKey: .openapi)
    }
    
    private enum CodingKeys: String, CodingKey {
        case port
        case token
        case openapi
    }
    
    func run() async throws {
#if canImport(OSLog)
        LoggingSystem.bootstrapWithOSLog()
#endif
        
        let calculator = Calculator()
		
        let host = String.localHostname
        print("MCP Server \(calculator.serverName) (\(calculator.serverVersion)) started with HTTP+SSE transport on http://\(host):\(port)/sse")
        
        let transport = HTTPSSETransport(server: calculator, port: port)
        
        // Set up authorization handler if token is provided
        if let requiredToken = token {
            transport.authorizationHandler = { token in
                guard let token else {
                    return .unauthorized("Missing bearer token")
                }
                
                guard token == requiredToken else {
                    return .unauthorized("Invalid bearer token")
                }
                
                return .authorized
            }
        }
        
        // Enable OpenAPI endpoints if requested
        transport.serveOpenAPI = openapi
        
        // Set up signal handling to shut down the transport on Ctrl+C
        signalHandler = SignalHandler(transport: transport)
        await signalHandler?.setup()
        
        // Run the server (blocking)
        try await transport.run()
    }
} 
