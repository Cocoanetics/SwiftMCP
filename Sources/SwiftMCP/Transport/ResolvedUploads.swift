import Foundation

/// Holds raw Data resolved from file-based uploads, keyed by parameter name.
/// Set as a task-local so `extractData(named:)` can pull directly without base64 round-tripping.
enum ResolvedUploads {
    @TaskLocal
    static var current: [String: Data]?
}
