//
//  MCPTool.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 08.03.25.
//

import Foundation

public struct MCPTool: Codable {
	
	public struct JSONSchema: Codable {
		
		public struct Property: Codable {
			public let type: String
			public let description: String?
			
			public init(type: String, description: String? = nil) {
				self.type = type
				self.description = description
			}
		}
		
		public let type: String
		public let properties: [String: Property]?
		public let required: [String]?
		
		public init(type: String, properties: [String : Property]?, required: [String]?) {
			self.type = type
			self.properties = properties
			self.required = required
		}
	}
	
    public let name: String
    public let description: String?
    public let inputSchema: JSONSchema
	
	public init(name: String, description: String?, inputSchema: JSONSchema) {
		self.name = name
		self.description = description
		self.inputSchema = inputSchema
	}
}



