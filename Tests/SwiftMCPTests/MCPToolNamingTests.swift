//
//  MCPToolNamingTests.swift
//  SwiftMCP
//

import Foundation
import Testing
@testable import SwiftMCP

// MARK: - Test Servers

/// Server with default naming (functionName)
@MCPServer(name: "DefaultNamingServer")
class DefaultNamingServer {
    /// Lists all windows
    @MCPTool
    func listWindows() -> [String] { [] }

    /// Gets user profile
    @MCPTool
    func getUserProfile() -> String { "profile" }
}

/// Server with snake_case naming
@MCPServer(name: "SnakeCaseServer", toolNaming: .snakeCase)
class SnakeCaseServer {
    /// Lists all windows
    @MCPTool
    func listWindows() -> [String] { [] }

    /// Gets user profile
    @MCPTool
    func getUserProfile() -> String { "profile" }

    /// Parses HTML content
    @MCPTool
    func parseHTMLContent() -> String { "parsed" }

    /// Explicit name override should win
    @MCPTool(name: "healthcheck")
    func checkHealth() -> String { "ok" }
}

/// Server with PascalCase naming
@MCPServer(name: "PascalCaseServer", toolNaming: .pascalCase)
class PascalCaseServer {
    /// Lists all windows
    @MCPTool
    func listWindows() -> [String] { [] }

    /// Gets user profile
    @MCPTool
    func getUserProfile() -> String { "profile" }

    /// Explicit name override should win
    @MCPTool(name: "healthcheck")
    func checkHealth() -> String { "ok" }
}

// MARK: - Tests

@Test("Default toolNaming (.functionName) preserves Swift function names")
func testDefaultNamingPreservesFunctionNames() {
    let server = DefaultNamingServer()
    let names = server.mcpToolMetadata.map(\.name)
    #expect(names.contains("listWindows"))
    #expect(names.contains("getUserProfile"))
}

@Test("snakeCase toolNaming transforms camelCase to snake_case")
func testSnakeCaseNaming() {
    let server = SnakeCaseServer()
    let names = server.mcpToolMetadata.map(\.name)
    #expect(names.contains("list_windows"))
    #expect(names.contains("get_user_profile"))
    #expect(names.contains("parse_html_content"))
}

@Test("Explicit @MCPTool(name:) override wins over server-level toolNaming")
func testExplicitNameOverrideWins() {
    let server = SnakeCaseServer()
    let names = server.mcpToolMetadata.map(\.name)
    // Explicit name: "healthcheck" should NOT be transformed to "check_health"
    #expect(names.contains("healthcheck"))
    #expect(!names.contains("check_health"))
}

@Test("pascalCase toolNaming transforms camelCase to PascalCase")
func testPascalCaseNaming() {
    let server = PascalCaseServer()
    let names = server.mcpToolMetadata.map(\.name)
    #expect(names.contains("ListWindows"))
    #expect(names.contains("GetUserProfile"))
}

@Test("pascalCase explicit @MCPTool(name:) override wins")
func testPascalCaseExplicitOverride() {
    let server = PascalCaseServer()
    let names = server.mcpToolMetadata.map(\.name)
    #expect(names.contains("healthcheck"))
    #expect(!names.contains("CheckHealth"))
}

@Test("snakeCase callTool dispatches with transformed name")
func testSnakeCaseCallTool() async throws {
    let server = SnakeCaseServer()
    let result = try await server.callTool("list_windows", arguments: [:])
    let array = result as! [String]
    #expect(array == [])
}

@Test("snakeCase callTool works for explicit override name")
func testSnakeCaseCallToolExplicitOverride() async throws {
    let server = SnakeCaseServer()
    let result = try await server.callTool("healthcheck", arguments: [:])
    let str = result as! String
    #expect(str == "ok")
}

@Test("snakeCase mcpToolMetadata property contains transformed names")
func testSnakeCaseMetadataProperty() {
    let server = SnakeCaseServer()
    let metadata = server.mcpToolMetadata.first(where: { $0.name == "get_user_profile" })
    #expect(metadata != nil)
    #expect(metadata?.name == "get_user_profile")
}

@Test("snakeCase mcpToolMetadata property does not contain original function name")
func testSnakeCaseMetadataPropertyNoOriginalName() {
    let server = SnakeCaseServer()
    let metadata = server.mcpToolMetadata.first(where: { $0.name == "getUserProfile" })
    #expect(metadata == nil)
}

@Test("MCPToolMetadata.renamed produces correct copy")
func testMetadataRenamed() {
    let original = MCPToolMetadata(
        name: "listWindows",
        description: "Lists windows",
        parameters: [],
        returnType: String.self,
        isAsync: false,
        isThrowing: false,
        isConsequential: true
    )
    let renamed = original.renamed("list_windows")
    #expect(renamed.name == "list_windows")
    #expect(renamed.description == "Lists windows")
    #expect(renamed.isConsequential == true)
    #expect(renamed.parameters.isEmpty)
}

@Test("tools/list via handleMessage returns transformed tool names")
func testToolsListReturnsTransformedNames() async throws {
    let server = SnakeCaseServer()

    // First initialize
    let initRequest = JSONRPCMessage.request(
        id: 1,
        method: "initialize",
        params: [
            "protocolVersion": "2025-06-18",
            "capabilities": .object([:]),
            "clientInfo": .object(["name": "test", "version": "1.0"])
        ]
    )
    _ = await server.handleMessage(initRequest)

    // Send initialized notification
    let initialized = JSONRPCMessage.notification(method: "notifications/initialized")
    _ = await server.handleMessage(initialized)

    // List tools
    let listRequest = JSONRPCMessage.request(id: 2, method: "tools/list", params: [:])
    guard let response = await server.handleMessage(listRequest) else {
        #expect(Bool(false), "Expected response")
        return
    }

    guard case .response(let resp) = response, let result = resp.result else {
        #expect(Bool(false), "Expected response with result")
        return
    }

    guard let toolsArray = result["tools"]?.value as? [[String: Any]] else {
        #expect(Bool(false), "Expected tools array")
        return
    }

    let toolNames = toolsArray.compactMap { $0["name"] as? String }
    #expect(toolNames.contains("list_windows"))
    #expect(toolNames.contains("get_user_profile"))
    #expect(toolNames.contains("parse_html_content"))
    #expect(toolNames.contains("healthcheck"))
    #expect(!toolNames.contains("listWindows"))
    #expect(!toolNames.contains("getUserProfile"))
}
