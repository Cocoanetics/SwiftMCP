import Foundation
import ArgumentParser
import SwiftMCP
import Logging
#if canImport(OSLog)
import OSLog
#endif

/**
 A command that connects to an MCP server and lists available tools.

 This mode supports both stdio and HTTP+SSE connections and can either:
 - Write the tools list as JSON to a file with `-o`
 - Print a readable description of tools and parameters to stdout
 */
struct ToolsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tools",
        abstract: "Connect to an MCP server and list available tools",
        discussion: """
  Connect to an MCP server using either HTTP+SSE or stdio and list tools.

  Examples:
    # List tools via HTTP+SSE
    SwiftMCPDemo tools --sse http://localhost:8080/sse

    # List tools via stdio
    SwiftMCPDemo tools --command npx --arg -y --arg @modelcontextprotocol/server-filesystem

    # Write tools list as JSON to a file
    SwiftMCPDemo tools --sse http://localhost:8080/sse -o tools.json
"""
    )

    @Option(name: .long, help: "SSE endpoint URL, e.g. http://localhost:8080/sse")
    var sse: String?

    @Option(name: .long, help: "HTTP header in Key:Value or Key=Value format (repeatable)")
    var header: [String] = []

    @Option(name: .long, help: "Command to run for stdio connection")
    var command: String?

    @Option(name: .long, parsing: .unconditionalSingleValue, help: "Command argument for stdio connection (repeatable)")
    var arg: [String] = []

    @Option(name: .long, help: "Working directory for stdio connection")
    var cwd: String?

    @Option(name: .long, help: "Environment variable in KEY=VALUE format (repeatable)")
    var env: [String] = []

    @Option(name: [.customShort("o"), .long], help: "Write tools list as JSON to this file")
    var output: String?

    func validate() throws {
        let hasSse = sse != nil
        let hasCommand = command != nil
        if hasSse == hasCommand {
            throw ValidationError("Specify exactly one connection: either --sse or --command.")
        }
    }

    func run() async throws {
#if canImport(OSLog)
        LoggingSystem.bootstrapWithOSLog()
#endif

        let config = try makeConfig()
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
            print(formatTools(tools))
        }
    }

    private func makeConfig() throws -> MCPServerConfig {
        if let sse {
            guard let url = URL(string: sse) else {
                throw ValidationError("Invalid --sse URL: \(sse)")
            }
            let headers = try parseHeaders(header)
            return .sse(config: MCPServerSseConfig(url: url, headers: headers))
        }

        guard let command else {
            throw ValidationError("Missing --command for stdio connection.")
        }
        let workingDirectory = cwd ?? FileManager.default.currentDirectoryPath
        let environment = try parseEnvironment(env)
        let stdioConfig = MCPServerStdioConfig(
            command: command,
            args: arg,
            workingDirectory: workingDirectory,
            environment: environment
        )
        return .stdio(config: stdioConfig)
    }

    private func parseHeaders(_ values: [String]) throws -> [String: String] {
        var headers: [String: String] = [:]
        for value in values {
            guard let (key, headerValue) = splitKeyValue(value, separators: [":", "="]) else {
                throw ValidationError("Invalid header '\(value)'. Use Key:Value or Key=Value.")
            }
            headers[key] = headerValue
        }
        return headers
    }

    private func parseEnvironment(_ values: [String]) throws -> [String: String] {
        var environment: [String: String] = [:]
        for value in values {
            guard let (key, envValue) = splitKeyValue(value, separators: ["="]) else {
                throw ValidationError("Invalid environment variable '\(value)'. Use KEY=VALUE.")
            }
            environment[key] = envValue
        }
        return environment
    }

    private func splitKeyValue(_ value: String, separators: [String]) -> (String, String)? {
        for separator in separators {
            if let range = value.range(of: separator) {
                let key = String(value[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                let val = String(value[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                if !key.isEmpty {
                    return (key, val)
                }
            }
        }
        return nil
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
