import Foundation

/// Configuration for an MCP server using standard input/output.
public struct MCPServerStdioConfig: Codable, Equatable, Sendable {
    /// The command to execute.
    public let command: String
    /// Command line arguments.
    public let args: [String]
    /// Working directory for the process.
    public let workingDirectory: String
    /// Environment variables.
    public let environment: [String: String]

    public init(command: String, args: [String], workingDirectory: String, environment: [String: String]) {
        self.command = command
        self.args = args
        self.workingDirectory = workingDirectory
        self.environment = environment
    }
}
