// Re-export Foundation.URL so any file that imports SwiftMCP can refer to
// `URL` without explicitly importing Foundation. The `@MCPServer` macro
// emits `URL`-typed parameters in the resource-handling code it adds to
// the user's class, and we don't want to require every `@MCPServer`'d
// type's source file to `import Foundation`.
@_exported import struct Foundation.URL

/// SwiftMCP is a framework for building Model-Controller-Protocol (MCP) servers.
///
/// The framework provides:
/// - Easy-to-use macros for exposing Swift functions to AI models
/// - Automatic JSON-RPC communication handling
/// - Type-safe parameter validation and conversion
/// - Support for async/await and error handling
/// - Multiple transport options (stdio, TCP+Bonjour, and HTTP/SSE)
/// - OpenAPI specification generation
/// - Resource management capabilities
///
/// To get started, see the ``MCPServer`` protocol and the ``MCPTool`` macro.
public enum SwiftMCP {
    /// The current version of the SwiftMCP framework
    public static let version = "1.0.0"
} 
