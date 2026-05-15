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
     Handles a JSON-RPC message and generates an appropriate response.

     - Parameter message: The JSON-RPC message to handle
     - Returns: A response message if one should be sent, nil otherwise
     */
    func handleMessage(_ message: JSONRPCMessage) async -> JSONRPCMessage?

    /// Called when the roots list has changed. Default implementation does nothing.
    func handleRootsListChanged() async
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

    /// Handles the roots list changed notification by retrieving the updated roots list.
    func handleRootsListChanged() async {}
}
