//
//  SchemaRepresentable.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 30.03.25.
//

import Foundation

/// Protocol for types that can be initialized from a dictionary
public protocol DictionaryInitializable {
	init(dictionary: [String: Any]) throws
}

/// Protocol for types that can represent themselves as a JSON Schema
public protocol SchemaRepresentable {
	/// Metadata about the schema
	static var __schemaMetadata: SchemaMetadata { get }
	
	/// The JSON Schema representation of this type
	static var schema: JSONSchema { get }
}

extension SchemaRepresentable {
	public static var schema: JSONSchema {
		return __schemaMetadata.schema
	}
}
