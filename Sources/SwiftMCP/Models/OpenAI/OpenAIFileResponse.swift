//
//  OpenAIFileResponse.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 08.03.25.
//

import Foundation

/// Represents a file response in the OpenAI format
@Schema
public struct File: Codable {
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

/// A collection of file responses
public struct OpenAIFileResponse: Codable {
    /// The array of file responses
    public let files: [File]
    
    /**
     Creates a new collection of file responses
     
     - Parameter files: The array of file responses
     */
    public init(files: [File]) {
        self.files = files
    }
    
    private enum CodingKeys: String, CodingKey {
        case files = "openaiFileResponse"
    }
} 
