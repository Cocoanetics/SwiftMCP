#if Server
import Foundation
import ArgumentParser
import SwiftMCP
import Logging

/**
 A command that starts an HTTP server with Server-Sent Events (SSE) support for SwiftMCP.
 */
final class HTTPSSECommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "httpsse",
        abstract: "Start an HTTP server with Server-Sent Events (SSE) support",
        discussion: """
  Start an HTTP server that supports Server-Sent Events (SSE) and JSON-RPC.

  Examples:
    # Basic usage
    SwiftMCPIntentsDemo httpsse --port 8080

    # With simple token authentication
    SwiftMCPIntentsDemo httpsse --port 8080 --token my-secret-token

    # With OAuth configuration from JSON file
    SwiftMCPIntentsDemo httpsse --port 8080 --oauth oauth-config.json

    # With OpenAPI support
    SwiftMCPIntentsDemo httpsse --port 8080 --openapi
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
        guard let server = IntentsDemoServerFactory.makeServer() else {
            logToStderr(IntentsDemoServerFactory.unavailableReason)
            throw ExitCode.failure
        }

        let host = ProcessInfo.processInfo.hostName
        print(
            "MCP Server \(server.serverName) (\(server.serverVersion)) started "
            + "with HTTP+SSE transport on http://\(host):\(port)/sse"
        )

        let transport = HTTPSSETransport(server: server, port: port)
        try configureAuthentication(on: transport)
        transport.serveOpenAPI = openapi

        // `serve(over:)` owns the run loop, traps SIGINT/SIGTERM, and drives an
        // ordered graceful shutdown of every transport — no hand-built
        // `ServiceGroup`.
        var transports: [any MCPTransport] = [transport]
        if let tcpTransport = makeTCPTransportIfNeeded(server: server) {
            transports.append(tcpTransport)
        }

        try await server.serve(
            over: transports,
            logger: Logging.Logger(label: "com.cocoanetics.SwiftMCP.Serve")
        )
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
    /// `serve(over:)` starts it by calling `run()`.
    private func makeTCPTransportIfNeeded(server: any MCPServer) -> TCPBonjourTransport? {
        guard tcp else { return nil }
        print("MCP Server \(server.serverName) will also expose a TCP+Bonjour transport")
        return TCPBonjourTransport(server: server)
    }
}
#endif
