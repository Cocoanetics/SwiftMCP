//
//  FileContent.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 06.04.25.
//


import Foundation

/// Contents of a File to be returned by a tool call
@Schema
public struct FileContent: Codable, Sendable {
    /// The name of the file
    public let name: String
    
    /// The MIME type of the file
    public let mimeType: String
    
    /**
	 The content of the file in base64 encoding
	 */
    public let content: Data
	
    /**
     Creates a new file response
     
     - Parameters:
       - name: The name of the file
       - mimeType: The MIME type of the file
       - content: The content of the file in base64 encoding
     */
    public init(name: String, mimeType: String, content: Data) {
        self.name = name
        self.mimeType = mimeType
        self.content = content
    }
    
    private enum CodingKeys: String, CodingKey {
        case name
        case mimeType = "mime_type"
        case content
    }
}
