import Foundation

/// Configuration for an MCP server using Server-Sent Events (SSE).
public struct MCPServerSseConfig: Codable, Equatable, Sendable {
    /// The URL of the SSE endpoint.
    public let url: URL
    /// HTTP headers to include in the request.
    public let headers: [String: String]

    public init(url: URL, headers: [String: String] = [:]) {
        self.url = url
        self.headers = headers
    }
}
