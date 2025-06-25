import Foundation
import ArgumentParser
import SwiftMCP
import Logging
#if canImport(OSLog)
import OSLog
#endif


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
  - Optional bearer token authentication or OAuth validation
  - Optional OpenAPI endpoints for AI plugin integration
  
  Examples:
    # Basic usage
    SwiftMCPDemo httpsse --port 8080
    
    # With authentication
    SwiftMCPDemo httpsse --port 8080 --token my-secret-token
    
    # With OpenAPI support
    SwiftMCPDemo httpsse --port 8080 --openapi

    # With OAuth
    SwiftMCPDemo httpsse --port 8080 \
        --oauth-issuer https://example.com \
        --oauth-token-endpoint https://example.com/oauth/token \
        --oauth-introspection-endpoint https://example.com/oauth/introspect \
        --oauth-jwks-endpoint https://example.com/.well-known/jwks.json
"""
    )
    
    @Option(name: .long, help: "The port to listen on")
    var port: Int
    
    @Option(name: .long, help: "Bearer token for authorization")
    var token: String?
    
    @Flag(name: .long, help: "Enable OpenAPI endpoints")
    var openapi: Bool = false

    @Option(name: .long, help: "OAuth issuer URL")
    var oauthIssuer: String?

    @Option(name: .long, help: "OAuth authorization endpoint")
    var oauthAuthorize: String?

    @Option(name: .long, help: "OAuth token endpoint")
    var oauthTokenEndpoint: String?

    @Option(name: .long, help: "OAuth introspection endpoint")
    var oauthIntrospectionEndpoint: String?

    @Option(name: .long, help: "OAuth JWKS endpoint")
    var oauthJWKS: String?

    @Option(name: .long, help: "OAuth audience")
    var oauthAudience: String?

    @Option(name: .long, help: "OAuth client identifier")
    var oauthClientID: String?

    @Option(name: .long, help: "OAuth client secret")
    var oauthClientSecret: String?

    @Option(name: .long, help: "OAuth dynamic client registration endpoint")
    var oauthRegistrationEndpoint: String?
    
    // Make this a computed property instead of stored property
    private var signalHandler: SignalHandler? = nil
    
    required init() {}
    
    // Add manual Decodable conformance
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.port = try container.decode(Int.self, forKey: .port)
        self.token = try container.decodeIfPresent(String.self, forKey: .token)
        self.openapi = try container.decode(Bool.self, forKey: .openapi)
        self.oauthIssuer = try container.decodeIfPresent(String.self, forKey: .oauthIssuer)
        self.oauthAuthorize = try container.decodeIfPresent(String.self, forKey: .oauthAuthorize)
        self.oauthTokenEndpoint = try container.decodeIfPresent(String.self, forKey: .oauthTokenEndpoint)
        self.oauthIntrospectionEndpoint = try container.decodeIfPresent(String.self, forKey: .oauthIntrospectionEndpoint)
        self.oauthJWKS = try container.decodeIfPresent(String.self, forKey: .oauthJWKS)
        self.oauthAudience = try container.decodeIfPresent(String.self, forKey: .oauthAudience)
        self.oauthClientID = try container.decodeIfPresent(String.self, forKey: .oauthClientID)
        self.oauthClientSecret = try container.decodeIfPresent(String.self, forKey: .oauthClientSecret)
        self.oauthRegistrationEndpoint = try container.decodeIfPresent(String.self, forKey: .oauthRegistrationEndpoint)
    }

    private enum CodingKeys: String, CodingKey {
        case port
        case token
        case openapi
        case oauthIssuer
        case oauthAuthorize
        case oauthTokenEndpoint
        case oauthIntrospectionEndpoint
        case oauthJWKS
        case oauthAudience
        case oauthClientID
        case oauthClientSecret
        case oauthRegistrationEndpoint
    }
    
    func run() async throws {
#if canImport(OSLog)
        LoggingSystem.bootstrapWithOSLog()
#endif
        
        let calculator = DemoServer()
		
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

        if let issuer = oauthIssuer,
           let tokenURLString = oauthTokenEndpoint,
           let issuerURL = URL(string: issuer),
           let tokenURL = URL(string: tokenURLString) {

            let authURL = URL(string: oauthAuthorize ?? issuer)
            let introspectURL = oauthIntrospectionEndpoint.flatMap { URL(string: $0) }
            let jwksURL = oauthJWKS.flatMap { URL(string: $0) }
            let regURL = oauthRegistrationEndpoint.flatMap { URL(string: $0) }

            transport.oauthConfiguration = OAuthConfiguration(
                issuer: issuerURL,
                authorizationEndpoint: authURL ?? tokenURL,
                tokenEndpoint: tokenURL,
                introspectionEndpoint: introspectURL,
                jwksEndpoint: jwksURL,
                audience: oauthAudience,
                clientID: oauthClientID,
                clientSecret: oauthClientSecret,
                registrationEndpoint: regURL
            )
        }
        
        // Set up signal handling to shut down the transport on Ctrl+C
        signalHandler = SignalHandler(transport: transport)
        await signalHandler?.setup()
        
        // Run the server (blocking)
        try await transport.run()
    }
} 
