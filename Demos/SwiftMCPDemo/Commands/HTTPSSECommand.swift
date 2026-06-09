#if Server
import Foundation
import ArgumentParser
import SwiftMCP
import Logging
import ServiceLifecycle
#if canImport(OSLog)
import OSLog
#endif

/**
 A command that starts an HTTP server with Server-Sent Events (SSE) support for SwiftMCP.
 
 This mode provides a long-running HTTP server that supports:
 - Server-Sent Events (SSE) for real-time updates
 - JSON-RPC over HTTP POST for function calls
 - Optional bearer token authentication
 - Optional OAuth/JWT validation from JSON configuration
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
    - OAuth configuration from JSON file
    - JWT validation (automatic when no introspection endpoint provided)
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

  OAuth Configuration JSON Format:
  {
    "issuer": "https://example.com",
    "authorization_endpoint": "https://example.com/authorize",
    "token_endpoint": "https://example.com/oauth/token",
    "introspection_endpoint": "https://example.com/oauth/introspect", // optional
    "jwks_uri": "https://example.com/.well-known/jwks.json", // optional
    "audience": "your-api-identifier", // optional
    "client_id": "client", // optional
    "client_secret": "secret", // optional
    "registration_endpoint": "https://example.com/oauth/register", // optional
    "transparent_proxy": true // optional, defaults to false
  }

  Note: If no introspection_endpoint is provided, JWT validation will be automatically enabled.

  Examples:
    # Basic usage
    SwiftMCPDemo httpsse --port 8080

    # With simple token authentication
    SwiftMCPDemo httpsse --port 8080 --token my-secret-token

    # With OAuth configuration from JSON file
    SwiftMCPDemo httpsse --port 8080 --oauth oauth-config.json

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

    @Flag(name: .long, help: "Also start TCP+Bonjour transport")
    var tcp: Bool = false

    @Option(name: .long, help: "Path to OAuth configuration JSON file")
    var oauth: String?

    required init() {}

    // Add manual Decodable conformance
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.port = try container.decode(Int.self, forKey: .port)
        self.token = try container.decodeIfPresent(String.self, forKey: .token)
        self.openapi = try container.decode(Bool.self, forKey: .openapi)
        self.oauth = try container.decodeIfPresent(String.self, forKey: .oauth)
        self.tcp = try container.decodeIfPresent(Bool.self, forKey: .tcp) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case port
        case token
        case openapi
        case oauth
        case tcp
    }

    func run() async throws {
#if canImport(OSLog)
        LoggingSystem.bootstrapWithOSLog()
#endif

        let calculator = DemoServer()

        let host = ProcessInfo.processInfo.hostName
        print(
            "MCP Server \(calculator.serverName) (\(calculator.serverVersion)) started "
            + "with HTTP+SSE transport on http://\(host):\(port)/sse"
        )

        let transport = HTTPSSETransport(server: calculator, port: port)
        try configureAuthentication(on: transport)
        transport.serveOpenAPI = openapi

        // Each transport is a `Service`. The `ServiceGroup` starts them, traps
        // SIGINT/SIGTERM, and drives an ordered graceful shutdown (with a
        // timeout) — replacing the bespoke signal handler.
        var services: [ServiceGroupConfiguration.ServiceConfiguration] = [
            .init(service: transport, successTerminationBehavior: .gracefullyShutdownGroup)
        ]
        if let tcpTransport = makeTCPTransportIfNeeded(server: calculator) {
            services.append(.init(service: tcpTransport, successTerminationBehavior: .gracefullyShutdownGroup))
        }

        let group = ServiceGroup(
            configuration: .init(
                services: services,
                gracefulShutdownSignals: [.sigterm, .sigint],
                logger: Logging.Logger(label: "com.cocoanetics.SwiftMCP.ServiceGroup")
            )
        )
        try await group.run()
    }

    private func configureAuthentication(on transport: HTTPSSETransport) throws {
        if let oauthConfigPath = oauth {
            try configureOAuth(on: transport, configPath: oauthConfigPath)
        } else if let requiredToken = token {
            transport.authorizationHandler = Self.makeTokenAuthorizationHandler(requiredToken: requiredToken)
            print("Simple token validation enabled")
        } else {
            transport.authorizationHandler = { _ in .authorized }
            print("No authentication configured - all requests will be accepted")
        }
    }

    private func configureOAuth(on transport: HTTPSSETransport, configPath: String) throws {
        do {
            let jsonConfig = try JSONOAuthConfiguration.load(from: configPath)
            transport.oauthConfiguration = try jsonConfig.toOAuthConfiguration()
            Self.logOAuthConfiguration(jsonConfig)
        } catch {
            print("Error loading OAuth configuration: \(error)")
            throw ExitCode.failure
        }
    }

    private static func logOAuthConfiguration(_ jsonConfig: JSONOAuthConfiguration) {
        print("OAuth validation enabled with issuer: \(jsonConfig.issuer)")
        if jsonConfig.transparentProxy == true {
            print("  Transparent proxy mode: enabled (server acts as OAuth provider)")
        }
        if jsonConfig.introspectionEndpoint == nil {
            print("  JWT validation: enabled (no introspection endpoint provided)")
        } else {
            print("  Token introspection: enabled")
        }
        if let audience = jsonConfig.audience {
            print("  Expected audience: \(audience)")
        }
        if let clientID = jsonConfig.clientID {
            print("  Expected client ID: \(clientID)")
        }
    }

    private static func makeTokenAuthorizationHandler(
        requiredToken: String
    ) -> HTTPSSETransport.AuthorizationHandler {
        return { token in
            guard let token else {
                return .unauthorized("Missing bearer token")
            }
            guard token == requiredToken else {
                return .unauthorized("Invalid bearer token")
            }
            return .authorized
        }
    }

    /// Builds the optional TCP+Bonjour transport. It is returned unstarted —
    /// the `ServiceGroup` starts it by calling `run()`.
    private func makeTCPTransportIfNeeded(server: DemoServer) -> TCPBonjourTransport? {
        guard tcp else { return nil }
        print("MCP Server \(server.serverName) will also expose a TCP+Bonjour transport")
        return TCPBonjourTransport(server: server)
    }
}
#endif
