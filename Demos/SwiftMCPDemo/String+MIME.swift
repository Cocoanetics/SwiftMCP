//
//  String+MIME.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 10.03.25.
//


// String+MIME.swift
// MIME-related extensions for String

import Foundation

#if os(macOS)
import UniformTypeIdentifiers
#endif

extension String {
    /// Get a file extension for a given MIME type
    /// - Parameter mimeType: The full MIME type (e.g., "text/plain", "image/jpeg")
    /// - Returns: An appropriate file extension (without the dot)
    public static func fileExtension(for mimeType: String) -> String? {
        #if os(macOS)
        // Try to get the UTType from the MIME type
        if let utType = UTType(mimeType: mimeType) {
            // Get the preferred file extension
            return utType.preferredFilenameExtension
        }
        return nil
        #else
        // Map common MIME types to extensions
        let mimeToExtension: [String: String] = [
            "image/jpeg": "jpg",
            "image/png": "png",
            "image/gif": "gif",
            "image/svg+xml": "svg",
            "application/pdf": "pdf",
            "text/plain": "txt",
            "text/html": "html",
            "application/msword": "doc",
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document": "docx",
            "application/vnd.ms-excel": "xls",
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet": "xlsx",
            "application/zip": "zip"
        ]
        
        return mimeToExtension[mimeType]
        #endif
    }
    
    /// Get MIME type for a file extension
    /// - Parameter fileExtension: The file extension (without dot)
    /// - Returns: The corresponding MIME type, or application/octet-stream if unknown
    public static func mimeType(for fileExtension: String) -> String {
        #if os(macOS)
        // Try to get UTType from file extension
        if let utType = UTType(filenameExtension: fileExtension),
           let mimeType = utType.preferredMIMEType {
            return mimeType
        }
        return "application/octet-stream"
        #else
        // Map common extensions to MIME types
        let extensionToMime: [String: String] = [
            "jpg": "image/jpeg",
            "jpeg": "image/jpeg",
            "png": "image/png",
            "gif": "image/gif",
            "svg": "image/svg+xml",
            "pdf": "application/pdf",
            "txt": "text/plain",
            "html": "text/html",
            "htm": "text/html",
            "doc": "application/msword",
            "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            "xls": "application/vnd.ms-excel",
            "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            "zip": "application/zip"
        ]
        
        return extensionToMime[fileExtension.lowercased()] ?? "application/octet-stream"
        #endif
    }
} 
