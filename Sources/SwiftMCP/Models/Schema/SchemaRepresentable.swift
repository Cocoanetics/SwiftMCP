//
//  SchemaRepresentable.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 30.03.25.
//

import Foundation

public protocol SchemaRepresentable: Codable {
	static var __schemaMetadata: SchemaMetadata { get }
	static var schema: JSONSchema { get }
}

extension SchemaRepresentable {
	public static var schema: JSONSchema {
		return __schemaMetadata.schema
	}
}
