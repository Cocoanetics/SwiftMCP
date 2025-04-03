//
//  MCPRessourceProviding.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 03.04.25.
//

import Foundation

public protocol MCPRessourceProviding {
	/**
	 The resources available on this server.
	 
	 Resources are data objects that can be accessed through the MCP protocol.
	 Each resource has a URI, name, description, and MIME type.
	 */
	var mcpResources: [MCPResource] { get async }
	
	/**
	 Retrieves a resource by its URI.
	 
	 - Parameter uri: The URI of the resource to retrieve
	 - Returns: The resource content if found, nil otherwise
	 - Throws: An error if the resource cannot be accessed
	 */
	func getResource(uri: URL) async throws -> MCPResourceContent?
}
