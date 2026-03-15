import Foundation

/// Provides synchronous upload URI resolution during tool call parameter extraction.
///
/// The resolver is set as a task-local before processing tool calls on HTTP transports
/// that support file uploads. It reads the uploaded file directly from disk using the
/// path stored during upload.
public enum UploadResolver {
    @TaskLocal
    static var current: UploadResolverContext?

    @TaskLocal
    static var pendingStore: PendingUploadStore?

    /// Resolve an `upload://` URI to its file data.
    /// Returns nil if no resolver is available or the URI is unknown.
    static func resolve(uri: String) -> Data? {
        current?.resolve(uri: uri)
    }
}

/// Context object that holds upload file paths for synchronous resolution.
final class UploadResolverContext: Sendable {
    private let filePaths: [String: String]  // uri → file path

    init(filePaths: [String: String]) {
        self.filePaths = filePaths
    }

    func resolve(uri: String) -> Data? {
        guard let path = filePaths[uri] else { return nil }
        return FileManager.default.contents(atPath: path)
    }
}
