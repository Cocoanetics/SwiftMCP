//
//  MCPToolProviding.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 03.04.25.
//

/**
 Protocol defining a service that provides callable tools for MCP.
 
 The `MCPToolProviding` protocol is a core service in the MCP architecture that allows
 servers to expose functions as remotely callable tools. Tools are functions that:
 - Have well-defined parameters and return types
 - Can be discovered and called through the MCP protocol
 - Are typically decorated with the `@MCPTool` macro for automatic metadata generation
 
 Servers implementing this protocol must:
 1. Provide a list of available tools via the `mcpTools` property
 2. Implement the `callTool` method to execute a tool by name with provided arguments
 
 When used with the `@MCPToolProvider` macro, conformance to this protocol can be
 automatically generated based on functions decorated with `@MCPTool`.
 
 Tools are discovered at runtime and can be called remotely through JSON-RPC,
 enabling flexible interaction between AI models and server capabilities.
 */
public protocol MCPToolProviding: MCPService {
	/**
	 The tools available on this server.
	 
	 Tools are functions that can be called remotely through the MCP protocol.
	 Each tool has a name, description, and set of parameters it accepts.
	 */
	var mcpTools: [MCPTool] { get }
	
	/**
	 Calls a tool by name with the provided arguments.
	 
	 - Parameters:
	   - name: The name of the tool to call
	   - arguments: The arguments to pass to the tool
	 - Returns: The result of the tool execution
	 - Throws: An error if the tool execution fails
	 */
	func callTool(_ name: String, arguments: [String: Sendable]) async throws -> Encodable & Sendable
}
