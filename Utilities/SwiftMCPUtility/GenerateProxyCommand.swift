import Foundation
import ArgumentParser
import SwiftMCP
import SwiftMCPUtilityCore

struct GenerateProxyCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "generate-proxy",
        abstract: "Generate a Swift proxy from MCP tools",
        discussion: """
  Connect to an MCP server, read the tools list, and generate a Swift proxy.

  Examples:
    SwiftMCPUtility generate-proxy --sse http://localhost:8080/sse -o ToolsProxy.swift
    SwiftMCPUtility generate-proxy --sse http://localhost:8080/sse --openapi http://localhost:8080/openapi.json -o ToolsProxy.swift
    SwiftMCPUtility generate-proxy --command "npx -y @modelcontextprotocol/server-filesystem"
    SwiftMCPUtility generate-proxy --config mcp.json --name FileToolsProxy
"""
    )

    @OptionGroup
    var connection: ConnectionOptions

    @Option(name: .long, help: "Name of the generated proxy type")
    var name: String?

    @Option(name: [.customShort("o"), .long], help: "Write the generated Swift file to this path")
    var output: String?

    @Option(name: .long, help: "OpenAPI JSON URL or file path to infer return types")
    var openapi: String?

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
        let serverName = await proxy.serverName
        let typeName = name ?? ProxyGenerator.defaultTypeName(serverName: serverName)
        let openAPIReturnInfo = try await OpenAPIProxyLoader.loadReturnSchemas(from: openapi)
        let source = ProxyGenerator.generate(typeName: typeName, tools: tools, openapiReturnSchemas: openAPIReturnInfo)
        let outputText = source.description
        try UtilitySupport.writeOutput(outputText, to: output)
    }
}
