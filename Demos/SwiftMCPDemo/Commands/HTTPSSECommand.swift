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
  - Optional bearer token authentication, JWT validation (using oauth-issuer/oauth-audience), or OAuth validation
  - Optional OpenAPI endpoints for AI plugin integration
  
  Examples:
    # Basic usage
    SwiftMCPDemo httpsse --port 8080
    
    # With simple token authentication
    SwiftMCPDemo httpsse --port 8080 --token my-secret-token
    
    # With JWT token validation
    SwiftMCPDemo httpsse --port 8080 --jwt-validation \
        --oauth-issuer https://dev-8ygj6eppnvjz8bm6.us.auth0.com/ \
        --oauth-audience https://dev-8ygj6eppnvjz8bm6.us.auth0.com/api/v2/
    
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

    @Option(name: .long, help: "OAuth audience")
    var oauthAudience: String?

    @Option(name: .long, help: "OAuth client identifier")
    var oauthClientID: String?

    @Option(name: .long, help: "OAuth client secret")
    var oauthClientSecret: String?

    @Flag(name: .long, help: "Enable JWT token validation (uses oauth-issuer and oauth-audience for validation)")
    var jwtValidation: Bool = false
    
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
        self.oauthAudience = try container.decodeIfPresent(String.self, forKey: .oauthAudience)
        self.oauthClientID = try container.decodeIfPresent(String.self, forKey: .oauthClientID)
        self.oauthClientSecret = try container.decodeIfPresent(String.self, forKey: .oauthClientSecret)
        self.jwtValidation = try container.decode(Bool.self, forKey: .jwtValidation)
    }

    private enum CodingKeys: String, CodingKey {
        case port
        case token
        case openapi
        case oauthIssuer
        case oauthAudience
        case oauthClientID
        case oauthClientSecret
        case jwtValidation
    }
    
    func run() async throws {
#if canImport(OSLog)
        LoggingSystem.bootstrapWithOSLog()
#endif
        
        let calculator = DemoServer()
		
        let host = String.localHostname
        print("MCP Server \(calculator.serverName) (\(calculator.serverVersion)) started with HTTP+SSE transport on http://\(host):\(port)/sse")
        
        let transport = HTTPSSETransport(server: calculator, port: port)
        
        // Set up authentication (priority: JWT > OAuth > simple token)
        if jwtValidation {
            // Use JWT validation via OAuth configuration
            let validator = JWTTokenValidator(
                expectedIssuer: oauthIssuer,
                expectedAudience: oauthAudience,
                expectedAuthorizedParty: oauthClientID
            )
            
            // Create a minimal OAuth configuration with our JWT validator
            let dummyIssuer = URL(string: oauthIssuer ?? "https://example.com")!
            let config = OAuthConfiguration(
                issuer: dummyIssuer,
                authorizationEndpoint: dummyIssuer.appendingPathComponent("authorize"),
                tokenEndpoint: dummyIssuer.appendingPathComponent("token"),
                tokenValidator: validator.validate
            )
            transport.oauthConfiguration = config
            
            print("JWT validation enabled:")
            if let issuer = oauthIssuer {
                print("  Expected issuer: \(issuer)")
            }
            if let audience = oauthAudience {
                print("  Expected audience: \(audience)")
            }
            if let clientID = oauthClientID {
                print("  Expected client ID (azp): \(clientID)")
            }
        } else if let requiredToken = token {
            // Simple token check
            transport.authorizationHandler = { token in
                guard let token else {
                    return .unauthorized("Missing bearer token")
                }
                
                guard token == requiredToken else {
                    return .unauthorized("Invalid bearer token")
                }
                
                return .authorized
            }
            print("Simple token validation enabled")
        } else if let issuerString = oauthIssuer,
                  let issuerURL = URL(string: issuerString) {
            // OAuth configuration
            if let config = await OAuthConfiguration(issuer: issuerURL,
                                                     audience: oauthAudience,
                                                     clientID: oauthClientID,
                                                     clientSecret: oauthClientSecret) {
                transport.oauthConfiguration = config
                print("OAuth validation enabled with issuer: \(issuerString)")
            }
        } else {
            print("No authentication configured - all requests will be accepted")
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
