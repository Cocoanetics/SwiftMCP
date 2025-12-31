import Foundation
import ArgumentParser
import SwiftMCP

struct CapabilitiesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "capabilities",
        abstract: "Describe MCP server capabilities",
        discussion: """
  Connect to an MCP server and print its capabilities in a readable format.

  Examples:
    SwiftMCPUtility capabilities --sse http://localhost:8080/sse
    SwiftMCPUtility capabilities --command "npx -y @modelcontextprotocol/server-filesystem" -o caps.txt
    SwiftMCPUtility capabilities --config mcp.json
"""
    )

    @OptionGroup
    var connection: ConnectionOptions

    @Option(name: [.customShort("o"), .long], help: "Write the capabilities description to this file")
    var output: String?

    func run() async throws {
        let config = try UtilitySupport.makeConfig(from: connection)
        let proxy = MCPServerProxy(config: config)

        defer {
            Task {
                await proxy.disconnect()
            }
        }

        try await proxy.connect()
        let description = formatCapabilities(
            name: await proxy.serverName,
            version: await proxy.serverVersion,
            capabilities: await proxy.serverCapabilities
        )
        try UtilitySupport.writeOutput(description, to: output)
    }

    private func formatCapabilities(
        name: String?,
        version: String?,
        capabilities: ServerCapabilities?
    ) -> String {
        var lines: [String] = []
        lines.append("Server: \(name ?? "unknown") \(version ?? "unknown")")

        guard let capabilities else {
            lines.append("Capabilities: none")
            return lines.joined(separator: "\n")
        }

        lines.append("Capabilities:")
        appendCapabilitiesSummary(capabilities, to: &lines)
        return lines.joined(separator: "\n")
    }

    private func appendCapabilitiesSummary(_ capabilities: ServerCapabilities, to lines: inout [String]) {
        if let tools = capabilities.tools {
            let listChanged = tools.listChanged == true ? "listChanged" : "no listChanged"
            lines.append("  - tools: supported (\(listChanged))")
        } else {
            lines.append("  - tools: not supported")
        }

        if let resources = capabilities.resources {
            let subscribe = resources.subscribe == true ? "subscribe" : "no subscribe"
            let listChanged = resources.listChanged == true ? "listChanged" : "no listChanged"
            lines.append("  - resources: supported (\(subscribe), \(listChanged))")
        } else {
            lines.append("  - resources: not supported")
        }

        if let prompts = capabilities.prompts {
            let listChanged = prompts.listChanged == true ? "listChanged" : "no listChanged"
            lines.append("  - prompts: supported (\(listChanged))")
        } else {
            lines.append("  - prompts: not supported")
        }

        if let logging = capabilities.logging {
            lines.append("  - logging: enabled=\(logging.enabled)")
        } else {
            lines.append("  - logging: not supported")
        }

        if let completions = capabilities.completions {
            let encoder = JSONEncoder()
            if let data = try? encoder.encode(completions),
               let string = String(data: data, encoding: .utf8) {
                lines.append("  - completions: \(string)")
            } else {
                lines.append("  - completions: supported")
            }
        } else {
            lines.append("  - completions: not supported")
        }

        if capabilities.experimental.isEmpty {
            lines.append("  - experimental: none")
        } else {
            let keys = capabilities.experimental.keys.sorted()
            lines.append("  - experimental: \(keys.joined(separator: ", "))")
        }
    }

    
}
