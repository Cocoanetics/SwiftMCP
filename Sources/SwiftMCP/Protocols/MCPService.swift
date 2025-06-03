//
//  MCPService.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 03.04.25.
//

/**
 Root protocol for MCP service capabilities.
 
 This protocol serves as a marker interface and base type for all MCP service protocols.
 In the Model-Client Protocol (MCP) architecture, services represent discrete capabilities
 that can be provided by a server, such as tools, resources, or other functionalities.
 
 Services can be discovered at runtime through the `MCPServer` protocol's service discovery
 methods, allowing for flexible composition of capabilities across servers.
 
 By separating capabilities into distinct service protocols that inherit from `MCPService`,
 the architecture supports:
 - Better separation of concerns
 - Runtime service discovery and composition
 - Ability to implement only the services needed by a particular server
 - Hierarchical aggregation of services from multiple servers
 */
public protocol MCPService
{

}
