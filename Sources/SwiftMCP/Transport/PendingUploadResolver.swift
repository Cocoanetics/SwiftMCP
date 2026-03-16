import Foundation

/// Provides access to the pending upload store during tool call processing.
///
/// Set as a task-local on HTTP transports that support file uploads,
/// allowing `MCPServer.resolveCIDPlaceholders` to access the store.
enum PendingUploadResolver {
    @TaskLocal
    static var current: PendingUploadStore?
}
