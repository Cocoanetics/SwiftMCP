#if Server
import Foundation
import ArgumentParser
import SwiftMCP
import Logging

/**
 A command that exposes the AppIntents demo server over TCP with Bonjour discovery.
 */
struct TCPBonjourCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tcp",
        abstract: "Expose the demo server over TCP with Bonjour discovery",
        discussion: """
  Start a TCP server that advertises via Bonjour (_mcp._tcp).

  Examples:
    SwiftMCPIntentsDemo tcp
    SwiftMCPIntentsDemo tcp --name "SwiftMCP Intents Demo" --port 0
"""
    )

    @Option(name: .long, help: "Bonjour service name to advertise (defaults to server name).")
    var name: String?

    @Option(name: .long, help: "Bonjour domain (default: local.).")
    var domain: String = "local."

    @Option(name: .long, help: "TCP port (0 = automatic).")
    var port: UInt16 = 0

    @Flag(name: .long, inversion: .prefixedNo, help: "Prefer IPv4 when binding.")
    var ipv4Only: Bool = true

    func run() async throws {
#if canImport(Network)
#if canImport(OSLog)
        LoggingSystem.bootstrapWithOSLog()
#endif
        guard let server = IntentsDemoServerFactory.makeServer() else {
            logToStderr(IntentsDemoServerFactory.unavailableReason)
            Foundation.exit(1)
        }

        do {
            logToStderr("MCP Server \(server.serverName) (\(server.serverVersion)) started with TCP+Bonjour transport")

            let bindPort = port == 0 ? nil : port
            // A server-less transport handed to `serve(over:)`: the framework
            // owns the run loop, SIGINT/SIGTERM trapping, and ordered graceful
            // shutdown — the consumer no longer hand-wires a `ServiceGroup`.
            let transport = TCPBonjourTransport(
                serviceName: name ?? server.serverName,
                serviceDomain: domain,
                port: bindPort,
                acceptLocalOnly: true,
                preferIPv4: ipv4Only
            )

            try await server.serve(
                over: [transport],
                logger: Logging.Logger(label: "com.cocoanetics.SwiftMCP.Serve")
            )
        } catch let error as TransportError {
            let errorMessage = """
                Transport Error: \(error.localizedDescription)
                """
            logToStderr(errorMessage)
            Foundation.exit(1)
        } catch {
            logToStderr("Error: \(error)")
            Foundation.exit(1)
        }
#else
        logToStderr("TCP+Bonjour transport requires macOS (Network framework not available)")
        Foundation.exit(1)
#endif
    }
}
#endif
