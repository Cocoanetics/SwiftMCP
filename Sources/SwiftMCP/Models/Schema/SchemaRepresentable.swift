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

// MARK: - MCPClientReturn default

/// Provides a default `MCPClientReturn` typealias for all `Decodable` types.
///
/// This resolves to `Self` by default. The `@Schema` macro overrides it for
/// single-array wrapper structs, so the generated proxy returns `[Element]`
/// instead of the wrapper.
public extension Decodable {
    typealias MCPClientReturn = Self
}
