//
//  SchemaRepresentable.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 30.03.25.
//

import Foundation

/// Protocol for types that can represent themselves as a JSON Schema
public protocol SchemaRepresentable: Sendable {

    /// The metadata for the schema
    static var schemaMetadata: SchemaMetadata { get }
}
