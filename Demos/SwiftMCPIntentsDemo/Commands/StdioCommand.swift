#if Server
import Foundation
import ArgumentParser
import SwiftMCP
import Logging
import NIOCore
import ServiceLifecycle
#if canImport(OSLog)
import OSLog
#endif

/**
 A command that processes JSON-RPC requests from standard input and writes responses to standard output.
 */
struct StdioCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stdio",
        abstract: "Read JSON-RPC requests from stdin and write responses to stdout",
        discussion: """
  Read JSON-RPC requests from stdin and write responses to stdout.

  Examples:
    # Basic usage
    SwiftMCPIntentsDemo stdio

    # With pipe
    echo '{"jsonrpc": "2.0", "method": "tools/list"}' | SwiftMCPIntentsDemo stdio
"""
    )

    /// A logger bound to stderr so `ServiceGroup` lifecycle messages never
    /// interleave with the JSON-RPC responses written to stdout.
    private static let lifecycleLogger: Logging.Logger = {
        var logger = Logging.Logger(label: "com.cocoanetics.SwiftMCP.ServiceGroup") {
            StreamLogHandler.standardError(label: $0)
        }
        logger.logLevel = .notice
        return logger
    }()

    func run() async throws {
#if canImport(OSLog)
        LoggingSystem.bootstrapWithOSLog()
#endif
        guard let server = IntentsDemoServerFactory.makeServer() else {
            logToStderr(IntentsDemoServerFactory.unavailableReason)
            Foundation.exit(1)
        }

        do {
            logToStderr("MCP Server \(server.serverName) (\(server.serverVersion)) started with Stdio transport")
            let transport = StdioTransport(server: server)

            // A `ServiceGroup` owns the run loop and traps SIGINT/SIGTERM,
            // driving a graceful shutdown of the transport. The lifecycle logs
            // go to stderr so they never corrupt the stdout JSON-RPC stream.
            let group = ServiceGroup(
                configuration: .init(
                    services: [
                        .init(service: transport, successTerminationBehavior: .gracefullyShutdownGroup)
                    ],
                    gracefulShutdownSignals: [.sigterm, .sigint],
                    logger: Self.lifecycleLogger
                )
            )
            try await group.run()
        } catch let error as TransportError {
            let errorMessage = """
                Transport Error: \(error.localizedDescription)
                """
            logToStderr(errorMessage)
            Foundation.exit(1)
        } catch let error as ChannelError {
            logToStderr("Channel Error: \(error)")
            Foundation.exit(1)
        } catch {
            logToStderr("Error: \(error)")
            Foundation.exit(1)
        }
    }
}

/// Function to log a message to stderr
func logToStderr(_ message: String) {
    guard let data = (message + "\n").data(using: .utf8) else { return }
    try? FileHandle.standardError.write(contentsOf: data)
}
#endif
