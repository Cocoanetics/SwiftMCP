import Foundation
import ArgumentParser
import SwiftMCP
import Logging
#if canImport(OSLog)
import OSLog
#endif

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
    
    private var signalHandler: SignalHandler? = nil
    
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
        
        let host = String.localHostname
        print("MCP Server \(server.serverName) (\(server.serverVersion)) started with HTTP+SSE transport on http://\(host):\(port)/sse")
        
        let transport = HTTPSSETransport(server: server, port: port)
        
        if let oauthConfigPath = oauth {
            do {
                let jsonConfig = try JSONOAuthConfiguration.load(from: oauthConfigPath)
                let oauthConfig = try jsonConfig.toOAuthConfiguration()
                transport.oauthConfiguration = oauthConfig
                
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
            } catch {
                print("Error loading OAuth configuration: \(error)")
                throw ExitCode.failure
            }
        } else if let requiredToken = token {
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
        } else {
            transport.authorizationHandler = { _ in
                return .authorized
            }
            print("No authentication configured - all requests will be accepted")
        }

        transport.serveOpenAPI = openapi
        
        var tcpTransport: TCPBonjourTransport?
        if tcp {
            let transport = TCPBonjourTransport(server: server)
            try await transport.start()
            tcpTransport = transport
            print("MCP Server \(server.serverName) started with TCP+Bonjour transport")
        }

        if let tcpTransport {
            signalHandler = SignalHandler(transports: [transport, tcpTransport])
        } else {
            signalHandler = SignalHandler(transport: transport)
        }
        await signalHandler?.setup()
        
        do {
            try await transport.run()
        } catch {
            if let tcpTransport {
                try? await tcpTransport.stop()
            }
            throw error
        }
    }
}

