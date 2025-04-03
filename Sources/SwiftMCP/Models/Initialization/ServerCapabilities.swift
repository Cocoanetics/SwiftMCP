//
//  defines.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 03.04.25.
//

import Foundation
@preconcurrency import AnyCodable

/// Represents the capabilities of an MCP server.
///
/// This struct defines the various capabilities that an MCP server can support,
/// including experimental features, logging, completions, prompts, resources, and tools.
/// These capabilities are communicated to clients during initialization to inform them
/// about what functionalities are available on the server.
public struct ServerCapabilities: Codable, Sendable {
	/// Experimental, non-standard capabilities that the server supports.
	public var experimental: [String: AnyCodable] = [:]
	
	/// Present if the server supports sending log messages to the client.
	public var logging: AnyCodable?
	
	/// Present if the server supports argument autocompletion suggestions.
	public var completions: AnyCodable?
	
	/// Present if the server offers any prompt templates.
	public var prompts: PromptsCapabilities?
	
	/// Present if the server offers any resources to read.
	public var resources: ResourcesCapabilities?
	
	/// Present if the server offers any tools to call.
	public var tools: ToolsCapabilities?
	
	/// Capabilities related to prompt templates.
	public struct PromptsCapabilities: Codable, Sendable {
		/// Whether this server supports notifications for changes to the prompt list.
		public var listChanged: Bool?
		
		public init(listChanged: Bool? = nil) {
			self.listChanged = listChanged
		}
	}
	
	/// Capabilities related to resources.
	public struct ResourcesCapabilities: Codable, Sendable {
		/// Whether this server supports subscribing to resource updates.
		public var subscribe: Bool?
		
		/// Whether this server supports notifications for changes to the resource list.
		public var listChanged: Bool?
		
		public init(subscribe: Bool? = nil, listChanged: Bool? = nil) {
			self.subscribe = subscribe
			self.listChanged = listChanged
		}
	}
	
	/// Capabilities related to tools.
	public struct ToolsCapabilities: Codable, Sendable {
		/// Whether this server supports notifications for changes to the tool list.
		public var listChanged: Bool?
		
		public init(listChanged: Bool? = nil) {
			self.listChanged = listChanged
		}
	}
}
