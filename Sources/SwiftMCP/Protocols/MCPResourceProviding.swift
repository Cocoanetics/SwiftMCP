//
//  MCPResourceProviding.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 03.04.25.
//

import Foundation

public protocol MCPResourceProviding {
	/**
	 The resources available on this server.
	 
	 Resources are data objects that can be accessed through the MCP protocol.
	 Each resource has a URI, name, description, and MIME type.
	 */
	var mcpResources: [MCPResource] { get async }
	
	/**
	 The resource templates available on this server.
	 
	 Resource templates define patterns for resources that can be dynamically created
	 or accessed. Each template has a URI pattern, name, description, and MIME type.
	 */
	var mcpResourceTemplates: [MCPResourceTemplate] { get async }
	
	/**
	 Retrieves a resource by its URI.
	 
	 - Parameter uri: The URI of the resource to retrieve
	 - Returns: The resource content if found, nil otherwise
	 - Throws: An error if the resource cannot be accessed
	 */
	func getResource(uri: URL) async throws -> [MCPResourceContent]
	
	/**
	 Handles non-template resources (e.g., file-based resources).
	 Override this method to provide custom resource content handling.
	 
	 - Parameters:
	   - uri: The URI of the resource
	 - Returns: The resource content
	 - Throws: An error if the resource cannot be accessed
	 */
	func getNonTemplateResource(uri: URL) async throws -> [MCPResourceContent]
}


extension MCPResourceProviding {
	
	/// Returns an array of all MCP resources defined in this type
	public var mcpResources: [any MCPResource] {
		get async {
			return []
		}
	}
	
	/// Resource templates with zero parameters are listed together with mcpResources
	var mcpStaticResources: [MCPResource]
	{
		// Find the resources without parameters
		let mirror = Mirror(reflecting: self)
		
		let array: [MCPResourceMetadata] = mirror.children.compactMap { child in
				
			guard let label = child.label,
					label.hasPrefix("__mcpResourceMetadata_") else {
				return nil
			}
			
			guard let metadata = child.value as? MCPResourceMetadata else {
				return nil
			}
			
			guard metadata.parameters.isEmpty else
			{
				return nil
			}
			
			return metadata
		}
		
		// Create individual resources for each URI template
		return array.flatMap { metadata in
			metadata.uriTemplates.compactMap { template in
				guard let url = URL(string: template) else { return nil }
				return SimpleResource(uri: url, name: metadata.name, description: metadata.description, mimeType: metadata.mimeType)
			}
		}
	}
	
	public func getNonTemplateResource(uri: URL) async throws -> [MCPResourceContent] {
		// Default implementation: returns an empty array, indicating no non-template resource found by default.
		// Implementers should override this to provide specific non-template resource handling.
		return []
	}
}
