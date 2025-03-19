import Foundation
import Logging

/// A transport that exposes an MCP server over standard input/output
public final class StdioTransport {
	private let server: MCPServer
	private let logger = Logger(label: "com.cocoanetics.SwiftMCP.StdioTransport")
	
	/// Initialize a new stdio transport
	/// - Parameter server: The MCP server to expose
	public init(server: MCPServer) {
		self.server = server
	}
	
	/// Start reading from stdin and writing to stdout
	public func run() async throws {
		while true {
			if let input = readLine(),
			   !input.isEmpty,
			   let data = input.data(using: .utf8) {
				
				logger.trace("Received input: \(input)")
				
				let request = try JSONDecoder().decode(JSONRPCMessage.self, from: data)
				
				// Handle the request
				if let response = await server.handleRequest(request) {
					let data = try JSONEncoder().encode(response)
					guard let json = String(data: data, encoding: .utf8) else {
						logger.error("Failed to encode response as UTF-8")
						continue
					}
					
					// Print the response and flush immediately
					print(json)
					fflush(stdout)
					logger.trace("Sent response: \(json)")
				}
			} else {
				// If no input is available, sleep briefly and try again
				try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds in nanoseconds
			}
		}
	}
}
