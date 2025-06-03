//
//  MCPResourceKind.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 03.04.25.
//

import Foundation

/**
 Represents the kind of content a resource can provide.
 
 Resources can provide either textual or binary data:
 - text: Plain text content
 - data: Binary data content
 */
public enum MCPResourceKind
{
    case text(String)

    case data(Data)
}
