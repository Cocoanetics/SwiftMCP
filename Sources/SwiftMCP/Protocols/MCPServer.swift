import Foundation

/**
 Protocol defining the interface for an MCP server.

 This protocol provides the core functionality required for an MCP (Model-Client Protocol) server.
 It is automatically implemented for classes or actors that are decorated with the `@MCPServer` macro.

 An MCP server provides:
 - Tool execution capabilities
 - Resource management
 - JSON-RPC message handling
 - Server metadata
 */
public protocol MCPServer {
    /**
     The name of the server.

     This name is used to identify the server in communications and logging.
     */
    var serverName: String { get }

    /**
     The version of the server.

     This version string helps clients understand the server's capabilities and compatibility.
     */
    var serverVersion: String { get }

    /**
     The description of the server.

     An optional description providing more details about the server's purpose and capabilities.
     */
    var serverDescription: String? { get }

    /**
     A human-friendly display name for the server, distinct from `serverName`
     (a programmatic identifier). Introduced in protocol version `2025-06-18`.
     */
    var serverTitle: String? { get }

    /**
     A URL for the server's website or homepage. Introduced in protocol version `2025-06-18`.
     */
    var serverWebsiteUrl: URL? { get }

    /**
     Handles a JSON-RPC message and generates an appropriate response.

     - Parameter message: The JSON-RPC message to handle
     - Returns: A response message if one should be sent, nil otherwise
     */
    func handleMessage(_ message: JSONRPCMessage) async -> JSONRPCMessage?

    /// Called when the roots list has changed. Default implementation does nothing.
    func handleRootsListChanged() async

    /// A lifecycle hook invoked once, after all transports have stopped, to
    /// release server-lifetime resources.
    ///
    /// Override this on a stateful server to tear down things that outlive a
    /// single request — child processes, a singleton lock, open files.
    /// ``serve(over:gracefulShutdownSignals:logger:)`` calls it **after the
    /// transport group has fully stopped**, so it always runs *last* and on
    /// *every* exit path (a graceful signal, a transport finishing, or a
    /// transport throwing). The default implementation does nothing.
    ///
    /// ```swift
    /// func shutdown() async {
    ///     await closeLiveAgents()   // no orphaned subprocesses
    ///     releaseSingletonLock()    // safe: transports already drained
    /// }
    /// ```
    func shutdown() async
}

// MARK: - Default Implementations
public extension MCPServer {
    /**
     The server's name, derived from the `@MCPServer` macro.
     */
    var serverName: String {
        Mirror(reflecting: self).children
            .first(where: { $0.label == "__mcpServerName" })?.value as? String ?? "UnknownServer"
    }

    /**
     The server's version, derived from the `@MCPServer` macro.
     */
    var serverVersion: String {
        Mirror(reflecting: self).children
            .first(where: { $0.label == "__mcpServerVersion" })?.value as? String ?? "UnknownVersion"
    }

    /**
     The server's description, derived from the `@MCPServer` macro.
     */
    var serverDescription: String? {
        Mirror(reflecting: self).children
            .first(where: { $0.label == "__mcpServerDescription" })?.value as? String
    }

    /**
     The server's display title, derived from the `@MCPServer(title:)` macro argument.
     */
    var serverTitle: String? {
        Mirror(reflecting: self).children
            .first(where: { $0.label == "__mcpServerTitle" })?.value as? String
    }

    /**
     The server's website URL, derived from the `@MCPServer(websiteUrl:)` macro argument.
     */
    var serverWebsiteUrl: URL? {
        // The macro stores the URL as a String (so generated code needs no
        // Foundation import in the consumer); convert here.
        (Mirror(reflecting: self).children
            .first(where: { $0.label == "__mcpServerWebsiteUrl" })?.value as? String)
            .flatMap(URL.init(string:))
    }

    /// Handles the roots list changed notification by retrieving the updated roots list.
    func handleRootsListChanged() async {}

    /// Default no-op lifecycle hook. Override on a stateful server to release
    /// server-lifetime resources after all transports have stopped.
    func shutdown() async {}
}
