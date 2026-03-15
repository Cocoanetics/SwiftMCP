import Foundation

/// Opt-in protocol that enables binary file upload support on the HTTP transport.
///
/// When your `MCPServer` conforms to this protocol, the transport registers a
/// `POST /mcp/uploads` endpoint and advertises the `experimental.uploads` capability.
///
/// Uploaded files are stored as temporary files scoped to the client session.
/// Tool functions that accept `Data` parameters can receive upload URIs
/// (e.g. `upload://session-id/file-id`) which are automatically resolved to the file contents.
///
/// ## Example
/// ```swift
/// extension MyServer: MCPFileUploadHandling {}
/// ```
///
/// Override `maxUploadSize` to change the default 50 MB limit:
/// ```swift
/// extension MyServer: MCPFileUploadHandling {
///     var maxUploadSize: Int { 100 * 1024 * 1024 }  // 100 MB
/// }
/// ```
public protocol MCPFileUploadHandling {
    /// Maximum upload size in bytes.
    var maxUploadSize: Int { get }
}

extension MCPFileUploadHandling {
    /// Default maximum upload size: 50 MB.
    public var maxUploadSize: Int { 50 * 1024 * 1024 }
}
