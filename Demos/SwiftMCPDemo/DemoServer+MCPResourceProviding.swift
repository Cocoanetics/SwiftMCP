////
////  DemoServer+MCPResourceProviding.swift
////  SwiftMCP
////
////  Created by Oliver Drobnik on 03.04.25.
////

import Foundation
import SwiftMCP

extension DemoServer
{
    /// Returns an array of all MCP resources defined in this type
    var mcpResources: [any MCPResource] {
        get async {
			return await getDynamicFileResources()
        }
    }
    
    /// Returns dynamic file-based resources from Downloads folder
    private func getDynamicFileResources() async -> [MCPResource] {
        // Get the Downloads folder URL
        guard let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            logToStderr("Could not get Downloads folder URL")
            return []
        }
        
        do {
            // List all files in the Downloads folder
            let fileURLs = try FileManager.default.contentsOfDirectory(
                at: downloadsURL,
                includingPropertiesForKeys: [.isRegularFileKey, .nameKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )
            
            // Filter to only include regular files
            let regularFileURLs = fileURLs.filter { url in
                do {
                    let resourceValues = try url.resourceValues(forKeys: [.isRegularFileKey])
                    return resourceValues.isRegularFile ?? false
                } catch {
                    return false
                }
            }
            
            // Create FileResource objects for each file
            return regularFileURLs.map { fileURL in
                // Get file attributes for description
                let fileAttributes: String
                do {
                    let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
                    let fileSize = attributes[.size] as? Int64 ?? 0
                    let modificationDate = attributes[.modificationDate] as? Date ?? Date()
                    let formatter = DateFormatter()
                    formatter.dateStyle = .medium
                    formatter.timeStyle = .short
                    fileAttributes = "Size: \(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)), Modified: \(formatter.string(from: modificationDate))"
                } catch {
                    fileAttributes = "File in Downloads folder"
                }
                
                return FileResource(
                    uri: fileURL,
                    name: fileURL.lastPathComponent,
                    description: fileAttributes
                )
            }
        } catch {
            logToStderr("Error listing files in Downloads folder: \(error.localizedDescription)")
            return []
        }
    }
    
    /// Override to handle file-based resources by reading actual file content
    public func getNonTemplateResource(uri: URL) async throws -> [MCPResourceContent] {
		// Check if the file exists
		guard FileManager.default.fileExists(atPath: uri.path) else {
			return []
		}
		
		// Get the resource content
		return try [FileResourceContent.from(fileURL: uri)]
    }
}
