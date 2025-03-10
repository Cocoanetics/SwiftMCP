import Foundation
import SwiftMCP

/// A resource implementation for files in the file system
public struct FileResource: MCPResource {
    /// The URI of the resource
    public let uri: URL
    
    /// The name of the resource
    public let name: String
    
    /// The description of the resource
    public let description: String
    
    /// The MIME type of the resource
    public let mimeType: String
    
    /// Creates a new FileResource
    /// - Parameters:
    ///   - uri: The URI of the file
    ///   - name: The name of the resource (defaults to the filename)
    ///   - description: The description of the resource (defaults to the file path)
    ///   - mimeType: The MIME type of the resource (defaults to a guess based on file extension)
    public init(uri: URL, name: String? = nil, description: String? = nil, mimeType: String? = nil) {
        self.uri = uri
        self.name = name ?? uri.lastPathComponent
        self.description = description ?? "File at \(uri.path)"
        
        if let mimeType = mimeType {
            self.mimeType = mimeType
        } else {
            // Try to determine MIME type from file extension
            let fileExtension = uri.pathExtension
            self.mimeType = String.mimeType(for: fileExtension)
        }
    }
}

/// A resource content implementation for files in the file system
public struct FileResourceContent: MCPResourceContent {
    /// The URI of the resource
    public let uri: URL
    
    /// The MIME type of the resource
    public let mimeType: String?
    
    /// The text content of the resource (if it's a text resource)
    public let text: String?
    
    /// The binary content of the resource (if it's a binary resource)
    public let blob: Data?
    
    /// Creates a new FileResourceContent
    /// - Parameters:
    ///   - uri: The URI of the file
    ///   - mimeType: The MIME type of the resource (optional)
    ///   - text: The text content of the resource (if it's a text resource)
    ///   - blob: The binary content of the resource (if it's a binary resource)
    public init(uri: URL, mimeType: String? = nil, text: String? = nil, blob: Data? = nil) {
        self.uri = uri
        self.mimeType = mimeType
        self.text = text
        self.blob = blob
    }
    
    /// Creates a new FileResourceContent from a file
    /// - Parameters:
    ///   - fileURL: The URL of the file
    ///   - mimeType: The MIME type of the resource (optional, will be determined from file extension if nil)
    /// - Throws: An error if the file cannot be read
    public static func from(fileURL: URL, mimeType: String? = nil) throws -> FileResourceContent {
        // Determine MIME type if not provided
        let determinedMimeType = mimeType ?? String.mimeType(for: fileURL.pathExtension)
        
        // Check if it's a text file
        let isTextFile = determinedMimeType.hasPrefix("text/")
        
        if isTextFile {
            // Read as text
            let text = try String(contentsOf: fileURL, encoding: .utf8)
            return FileResourceContent(uri: fileURL, mimeType: determinedMimeType, text: text)
        } else {
            // Read as binary
            let data = try Data(contentsOf: fileURL)
            return FileResourceContent(uri: fileURL, mimeType: determinedMimeType, blob: data)
        }
    }
} 