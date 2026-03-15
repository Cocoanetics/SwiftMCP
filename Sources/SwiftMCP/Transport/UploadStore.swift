import Foundation

/// Metadata about an uploaded file.
public struct UploadedFile: Codable, Sendable {
    /// The upload URI (e.g. `upload://session-id/file-id`).
    public let uri: String
    /// Size of the uploaded file in bytes.
    public let size: Int
    /// Content type from the request, if provided.
    public let contentType: String?
    /// Original filename from Content-Disposition, if provided.
    public let filename: String?
    /// Path to the temporary file on disk.
    public let path: String
}

/// Session-scoped temporary file storage for binary uploads.
actor UploadStore {
    private var files: [String: UploadedFile] = [:]
    private let baseDirectory: URL

    init() {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftmcp-uploads", isDirectory: true)
        baseDirectory = tmp
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    /// Store uploaded data as a temp file and return the metadata.
    func store(
        data: Data,
        sessionID: UUID,
        contentType: String?,
        filename: String?
    ) throws -> UploadedFile {
        let fileID = UUID().uuidString
        let sessionDir = baseDirectory
            .appendingPathComponent(sessionID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)

        let ext = Self.fileExtension(for: contentType, filename: filename)
        let filePath = sessionDir.appendingPathComponent(fileID + ext)
        try data.write(to: filePath)

        let uri = "upload://\(sessionID.uuidString)/\(fileID)"
        let upload = UploadedFile(
            uri: uri,
            size: data.count,
            contentType: contentType,
            filename: filename,
            path: filePath.path
        )
        files[uri] = upload
        return upload
    }

    /// Resolve an upload URI to the file data.
    func resolve(uri: String) -> Data? {
        guard let upload = files[uri] else { return nil }
        return FileManager.default.contents(atPath: upload.path)
    }

    /// Resolve an upload URI to file metadata.
    func metadata(for uri: String) -> UploadedFile? {
        files[uri]
    }

    /// Remove all uploads for a session.
    func removeAll(sessionID: UUID) {
        let prefix = "upload://\(sessionID.uuidString)/"
        let toRemove = files.keys.filter { $0.hasPrefix(prefix) }
        for key in toRemove {
            if let upload = files.removeValue(forKey: key) {
                try? FileManager.default.removeItem(atPath: upload.path)
            }
        }

        // Remove the session directory
        let sessionDir = baseDirectory
            .appendingPathComponent(sessionID.uuidString, isDirectory: true)
        try? FileManager.default.removeItem(at: sessionDir)
    }

    /// Returns a snapshot of all upload URI → file path mappings for a session.
    func filePaths(for sessionID: UUID) -> [String: String] {
        let prefix = "upload://\(sessionID.uuidString)/"
        var result: [String: String] = [:]
        for (uri, upload) in files where uri.hasPrefix(prefix) {
            result[uri] = upload.path
        }
        return result
    }

    /// Remove all uploads and the base directory.
    func removeAll() {
        for upload in files.values {
            try? FileManager.default.removeItem(atPath: upload.path)
        }
        files.removeAll()
        try? FileManager.default.removeItem(at: baseDirectory)
    }

    private static func fileExtension(for contentType: String?, filename: String?) -> String {
        // Try to get extension from filename first
        if let filename, let dotIndex = filename.lastIndex(of: ".") {
            return String(filename[dotIndex...])
        }

        // Fall back to content type
        switch contentType?.lowercased() {
        case "image/png": return ".png"
        case "image/jpeg": return ".jpg"
        case "image/gif": return ".gif"
        case "image/webp": return ".webp"
        case "application/pdf": return ".pdf"
        case "application/json": return ".json"
        case "text/plain": return ".txt"
        case "text/csv": return ".csv"
        case "application/zip": return ".zip"
        case "application/octet-stream": return ".bin"
        default: return ""
        }
    }
}
