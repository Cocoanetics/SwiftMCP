//
//  JSONSchema.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 08.03.25.
//

import Foundation

/// A simplified representation of JSON Schema for use in the macros
public indirect enum JSONSchema: Sendable {
    /// A string schema
    case string(description: String? = nil, format: String? = nil, enumValues: [String]? = nil)
    
    /// A number schema
    case number(description: String? = nil)
    
    /// A boolean schema
    case boolean(description: String? = nil)
    
    /// An array schema
    case array(items: JSONSchema, description: String? = nil)
    
    /// An object schema
    case object(properties: [String: JSONSchema], required: [String] = [], description: String? = nil)
    
    /// An enum schema with possible values
    case `enum`(values: [String], description: String? = nil)
} 
