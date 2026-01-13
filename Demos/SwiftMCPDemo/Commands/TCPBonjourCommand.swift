import Foundation
import ArgumentParser
import SwiftMCP
import Logging
#if canImport(OSLog)
import OSLog
#endif

/**
 A command that exposes the demo server over TCP with Bonjour discovery.
*/
struct TCPBonjourCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tcp",
        abstract: "Expose the demo server over TCP with Bonjour discovery",
        discussion: """
  Start a TCP server that advertises via Bonjour (_mcp._tcp).

  Examples:
    SwiftMCPDemo tcp
    SwiftMCPDemo tcp --name "SwiftMCP Demo" --port 0
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
#if canImport(OSLog)
        LoggingSystem.bootstrapWithOSLog()
#endif

        let calculator = DemoServer()

        do {
            logToStderr("MCP Server \(calculator.serverName) (\(calculator.serverVersion)) started with TCP+Bonjour transport")

            let bindPort = port == 0 ? nil : port
            let transport = TCPBonjourTransport(
                server: calculator,
                serviceName: name,
                serviceType: "_mcp._tcp",
                serviceDomain: domain,
                port: bindPort,
                acceptLocalOnly: true,
                preferIPv4: ipv4Only
            )
            try await transport.run()
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
    }
}
