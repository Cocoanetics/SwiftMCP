//
//  OpenAIFileResponse.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 08.03.25.
//

import Foundation

/// One or more files being returned
@Schema
public struct OpenAIFileResponse: Codable, Sendable {
/// The array of file responses
    public let openaiFileResponse: [FileContent]

/**
     Creates a new collection of file responses
     
     - Parameter files: The array of file responses
     */
    public init(files: [FileContent]) {
        self.openaiFileResponse = files
    }
}
