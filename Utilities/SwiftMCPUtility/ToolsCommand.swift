import Foundation
import ArgumentParser
import SwiftMCP

struct ToolsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tools",
        abstract: "List tools from an MCP server",
        discussion: """
  Connect to an MCP server using either HTTP+SSE or stdio and list tools.

  Examples:
    SwiftMCPUtility tools --sse http://localhost:8080/sse
    SwiftMCPUtility tools --command "npx -y @modelcontextprotocol/server-filesystem"
    SwiftMCPUtility tools --config mcp.json
    SwiftMCPUtility tools --sse http://localhost:8080/sse -o tools.json
"""
    )

    @OptionGroup
    var connection: ConnectionOptions

    @Option(name: [.customShort("o"), .long], help: "Write tools list as JSON to this file")
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
        let tools = try await proxy.listTools()

        if let output {
            try writeTools(tools, to: output)
        } else {
            let description = formatTools(tools)
            try UtilitySupport.writeOutput(description, to: nil)
        }
    }

    private func writeTools(_ tools: [MCPTool], to path: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(tools)
        let url = URL(fileURLWithPath: path)
        try data.write(to: url, options: .atomic)
    }

    private func formatTools(_ tools: [MCPTool]) -> String {
        let sortedTools = tools.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        var lines: [String] = []
        lines.append("Tools (\(sortedTools.count)):")

        for tool in sortedTools {
            lines.append("")
            lines.append(tool.name)
            if let description = tool.description, !description.isEmpty {
                lines.append("  \(description)")
            }
            appendSchemaDetails(tool.inputSchema, to: &lines)
        }

        return lines.joined(separator: "\n")
    }

    private func appendSchemaDetails(_ schema: JSONSchema, to lines: inout [String]) {
        switch schema {
            case .object(let object):
                if object.properties.isEmpty {
                    lines.append("  Parameters: none")
                    return
                }

                let required = Set(object.required)
                lines.append("  Parameters:")
                for name in object.properties.keys.sorted() {
                    guard let propertySchema = object.properties[name] else { continue }
                    let requiredSuffix = required.contains(name) ? " (required)" : " (optional)"
                    let typeDescription = describeSchema(propertySchema)
                    let detail = schemaDescription(propertySchema)
                    if let detail, !detail.isEmpty {
                        lines.append("    - \(name)\(requiredSuffix): \(typeDescription) - \(detail)")
                    } else {
                        lines.append("    - \(name)\(requiredSuffix): \(typeDescription)")
                    }
                }
            default:
                lines.append("  Input schema: \(describeSchema(schema))")
        }
    }

    private func describeSchema(_ schema: JSONSchema) -> String {
        switch schema {
            case .string(_, _, let format, _, _):
                if let format, !format.isEmpty {
                    return "string (\(format))"
                }
                return "string"
            case .number:
                return "number"
            case .boolean:
                return "boolean"
            case .array(let items, _, _):
                return "array<\(describeSchema(items))>"
            case .object:
                return "object"
            case .enum(let values, _, _, _):
                if values.isEmpty {
                    return "enum"
                }
                return "enum [\(values.joined(separator: ", "))]"
        }
    }

    private func schemaDescription(_ schema: JSONSchema) -> String? {
        switch schema {
            case .string(_, let description, _, _, _):
                return description
            case .number(_, let description, _, _):
                return description
            case .boolean(_, let description, _):
                return description
            case .array(_, _, let description):
                return description
            case .object(let object):
                return object.description
            case .enum(_, _, let description, _):
                return description
        }
    }
}
