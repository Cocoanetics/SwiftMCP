import Foundation

/// Whether the current platform can run stdio-based MCP servers.
///
/// Stdio connections (including the in-process bridge, which wraps
/// `MCPServerProcess`) require `Foundation.Process`, which SwiftMCP only
/// supports on macOS and Linux — see the `#if os(macOS) || os(Linux)` gate in
/// `MCPServerProcess`. On other platforms the stdio connection is a stub that
/// throws `.unsupportedPlatform`, so the corresponding tests are skipped.
let isStdioProcessSupported: Bool = {
    #if os(macOS) || os(Linux)
    return true
    #else
    return false
    #endif
}()
