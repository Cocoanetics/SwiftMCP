import Foundation
import Logging

/**
 Protocol defining the common interface for MCP (Model Context Protocol) transports.
 
 Transport implementations handle the communication layer between clients and the MCP server.
 Each transport type provides a different way to interact with the server:
 
 - HTTP+SSE: Provides HTTP endpoints with Server-Sent Events for real-time updates
 - Stdio: Uses standard input/output for command-line integration
 
 - Important: All transport implementations must be thread-safe and handle concurrent requests appropriately.

 - Note: Transport implementations should properly clean up resources in their `stop()` method.

 - Note: This is the original, server-coupled transport abstraction. The newer
   ``MCPConnection``/``MCPTransport`` boundary plus
   ``MCPServer/serve(over:gracefulShutdownSignals:logger:)`` decouples transports
   from the server; new transports should prefer that model. `Transport` remains
   the byte-level primitive that ``Session`` writes outbound bytes through.

 ## Example Usage
 ```swift
 final class MyTransport: Transport {
     let server: MCPServer
     let logger = Logger(label: "com.example.MyTransport")

     init(server: MCPServer) {
         self.server = server
     }

     func start() async throws {
         // Initialize and start your transport
     }

     func run() async throws {
         try await start()
         // Block until stopped
     }

     func stop() async throws {
         // Clean up resources
     }

     func send(_ data: Data) async throws {
         // Deliver the bytes to the connected client
     }
 }
 ```
 */
public protocol Transport: AnyObject, Sendable {
/**
     Logger instance for this transport.

     Used to log transport-specific events, errors, and debug information.
     Each transport implementation should use a unique label for its logger.
     */
    var logger: Logger { get }

/**
     Start the transport in a non-blocking way.
     
     This method should initialize the transport and make it ready to handle requests,
     but should return immediately without blocking the calling thread.
     
     - Throws: Any errors that occur during startup, such as:
               - Port binding failures
               - Configuration errors
               - Resource allocation failures
     
     - Important: This method should be idempotent. Calling it multiple times should not create
                 multiple instances of the transport.
     */
    func start() async throws

/**
     Run the transport and block until stopped.
     
     This method should start the transport if it hasn't been started yet and then
     block until the transport is explicitly stopped or encounters a fatal error.
     
     - Throws: Any errors that occur during operation, such as:
               - Startup errors if the transport hasn't been started
               - Fatal runtime errors
               - Shutdown errors
     
     - Note: This is typically used for command-line tools or services that should
             run until explicitly terminated.
     */
    func run() async throws

/**
     Stop the transport gracefully.
     
     This method should:
     1. Stop accepting new connections/requests
     2. Complete any in-flight requests if possible
     3. Release all resources
     4. Shut down cleanly
     
     - Throws: Any errors that occur during shutdown, such as:
               - Resource cleanup failures
               - Timeout errors
               - IO errors
     
     - Important: This method should be idempotent. Calling it multiple times should
                 not cause errors.
     */
    func stop() async throws

    /// Send raw data to the client.
    ///
    /// Transport implementations have to provide the concrete mechanism for
    /// delivering the bytes back to the connected client.
    func send(_ data: Data) async throws
}
