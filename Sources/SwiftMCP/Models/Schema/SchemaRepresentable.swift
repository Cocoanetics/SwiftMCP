//
//  SchemaRepresentable.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 30.03.25.
//

import Foundation

public protocol SchemaRepresentable {
	var schema: JSONSchema { get }
}
