#if canImport(Glibc)
@preconcurrency import Glibc
#endif

import Foundation
import Logging

/// A transport that exposes an MCP server over standard input/output.
///
/// This transport allows communication with an MCP server through standard input and output streams,
/// making it suitable for command-line interfaces and pipe-based communication.
public final class StdioTransport: Transport, @unchecked Sendable {
	/// The MCP server instance that this transport exposes.
	///
	/// This server handles the actual business logic while the transport handles I/O.
	public let server: MCPServer

	/// Logger instance for logging transport activity.
	///
	/// Used to track input/output operations and error conditions during transport operation.
	public let logger = Logger(label: "com.cocoanetics.SwiftMCP.StdioTransport")

	/// Actor to handle running state in a thread-safe manner.
	private actor TransportState {
		var isRunning: Bool = false

		func start() {
			isRunning = true
		}

		func stop() {
			isRunning = false
		}

		func isCurrentlyRunning() -> Bool {
			return isRunning
		}
	}

	private let state = TransportState()

	/// Initializes a new StdioTransport with the given MCP server.
	///
	/// - Parameter server: The MCP server to expose over standard input/output.
	public init(server: MCPServer) {
		self.server = server
	}

	/// Starts reading from stdin asynchronously in a non-blocking manner.
	///
	/// This method initiates a background task that processes input continuously until stopped.
	/// The background task reads JSON-RPC messages from stdin and forwards them to the MCP server.
	///
	/// - Throws: An error if the transport fails to start or process input.
	public func start() async throws {
		await state.start()

		// Capture immutable properties in a @Sendable closure.
		Task { @Sendable in
			do {
				while await state.isCurrentlyRunning() {
					if let input = readLine(),
					   !input.isEmpty,
					   let data = input.data(using: .utf8) {

						logger.trace("Received input: \(input)")

						let request = try JSONDecoder().decode(JSONRPCMessage.self, from: data)

						// Handle the request.
						if let response = await server.handleRequest(request) {
							let data = try JSONEncoder().encode(response)
							guard let json = String(data: data, encoding: .utf8) else {
								logger.error("Failed to encode response as UTF-8")
								continue
							}

							// Print the response and flush immediately using the StdoutActor.
							await StdoutActor.shared.printAndFlush(json)
							logger.trace("Sent response: \(json)")
						}
					} else {
						// If no input is available, sleep briefly and try again.
						try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
					}
				}
			} catch {
				logger.error("Error processing input: \(error)")
			}
		}
	}

	/// Runs the transport synchronously and blocks until the transport is stopped.
	///
	/// This method processes input directly on the calling task and will not return until
	/// `stop()` is called from another task.
	///
	/// - Throws: An error if the transport fails to process input.
	public func run() async throws {
		await state.start()

		while await state.isCurrentlyRunning() {
			if let input = readLine(),
			   !input.isEmpty,
			   let data = input.data(using: .utf8) {

				logger.trace("Received input: \(input)")

				let request = try JSONDecoder().decode(JSONRPCMessage.self, from: data)

				// Handle the request.
				if let response = await server.handleRequest(request) {
					let data = try JSONEncoder().encode(response)
					guard let json = String(data: data, encoding: .utf8) else {
						logger.error("Failed to encode response as UTF-8")
						continue
					}

					// Print the response and flush immediately using the StdoutActor.
					await StdoutActor.shared.printAndFlush(json)
					logger.trace("Sent response: \(json)")
				}
			} else {
				// If no input is available, sleep briefly and try again.
				try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
			}
		}
	}

	/// Stops the transport.
	///
	/// This method stops processing input from stdin. Any pending input will be discarded.
	///
	/// - Throws: An error if the transport fails to stop cleanly.
	public func stop() async throws {
		await state.stop()
	}
}
