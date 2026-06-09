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
 
 This is the default mode of operation for the SwiftMCP demo. It's designed to:
 - Read JSON-RPC requests line by line from stdin
 - Process each request using the configured MCP server
 - Write JSON-RPC responses to stdout
 - Log status messages to stderr to avoid interfering with the JSON-RPC protocol
 
 This mode is particularly useful for:
 - Integration with other tools via Unix pipes
 - Testing and debugging MCP functions
 - Scripting and automation
 */
struct StdioCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stdio",
        abstract: "Read JSON-RPC requests from stdin and write responses to stdout",
        discussion: """
  Read JSON-RPC requests from stdin and write responses to stdout.

  This mode is perfect for integration with other tools via pipes.

  Examples:
    # Basic usage
    SwiftMCPDemo stdio

    # With pipe
    echo '{"jsonrpc": "2.0", "method": "add", "params": [1, 2]}' | SwiftMCPDemo stdio
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

        let calculator = DemoServer()

        do {
            // need to output to stderror or else npx complains
			logToStderr("MCP Server \(calculator.serverName) (\(calculator.serverVersion)) started with Stdio transport")

            let transport = StdioTransport(server: calculator)

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
            // Handle transport errors
            let errorMessage = """
                Transport Error: \(error.localizedDescription)
                """
			logToStderr(errorMessage)
            Foundation.exit(1)
        } catch let error as ChannelError {
            // Handle specific channel errors
			logToStderr("Channel Error: \(error)")
            Foundation.exit(1)
        } catch {
            // Handle any other errors
			logToStderr("Error: \(error)")
            Foundation.exit(1)
        }
    }
}
#endif
