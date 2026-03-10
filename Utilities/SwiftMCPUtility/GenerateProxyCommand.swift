import Foundation
import ArgumentParser
import SwiftMCP
import SwiftMCPUtilityCore

struct GenerateProxyCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "generate-proxy",
        abstract: "Generate a Swift proxy from MCP server surfaces",
        discussion: """
  Connect to an MCP server, inspect its advertised capabilities, and generate a Swift proxy
  for available tools, resources, and prompts.

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
        let supportsResources = await proxy.serverCapabilities?.resources != nil
        let supportsPrompts = await proxy.serverCapabilities?.prompts != nil
        let resources = supportsResources ? ((try? await proxy.listResources()) ?? []) : []
        let resourceTemplates = supportsResources ? ((try? await proxy.listResourceTemplates()) ?? []) : []
        let prompts = supportsPrompts ? ((try? await proxy.listPrompts()) ?? []) : []
        let serverName = await proxy.serverName
        let serverVersion = await proxy.serverVersion
        let serverDescription = await proxy.serverDescription
        let typeName = name ?? ProxyGenerator.defaultTypeName(serverName: serverName)
        let openAPIReturnInfo = try await OpenAPIProxyLoader.loadReturnSchemas(from: openapi)
        let fileName = output.map { URL(fileURLWithPath: $0).lastPathComponent }
        let sourceDescription = connectionSourceDescription()
        let headerMetadata = ProxyGenerator.HeaderMetadata(
            fileName: fileName ?? "\(typeName).swift",
            serverName: serverName,
            serverVersion: serverVersion,
            serverDescription: serverDescription,
            source: sourceDescription,
            openAPI: openapi
        )
        let source = ProxyGenerator.generate(
            typeName: typeName,
            tools: tools,
            resources: resources,
            resourceTemplates: resourceTemplates,
            prompts: prompts,
            supportsResources: supportsResources,
            supportsPrompts: supportsPrompts,
            openapiReturnSchemas: openAPIReturnInfo,
            fileName: fileName,
            headerMetadata: headerMetadata
        )
        let outputText = source.description
        try UtilitySupport.writeOutput(outputText, to: output)
    }

    private func connectionSourceDescription() -> String? {
        if let configPath = connection.config {
            return "config \(configPath)"
        }
        if let sse = connection.sse {
            return "sse \(sse)"
        }
        if let command = connection.command {
            return "command \(command)"
        }
        return nil
    }
}
