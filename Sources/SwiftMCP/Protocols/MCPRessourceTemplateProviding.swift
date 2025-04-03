//
//  MCPRessourceTemplateProviding.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 03.04.25.
//

import Foundation

public protocol MCPRessourceTemplateProviding {
	/**
	 The resource templates available on this server.
	 
	 Resource templates define patterns for resources that can be dynamically created
	 or accessed. Each template has a URI pattern, name, description, and MIME type.
	 */
	var mcpResourceTemplates: [MCPResourceTemplate] { get async }
}
