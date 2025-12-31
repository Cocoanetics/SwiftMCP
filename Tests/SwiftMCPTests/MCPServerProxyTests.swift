import Testing
import SwiftMCP
import Foundation

struct MCPServerProxyTests {
    static let mcpServerURL = URL(string: "http://\(String.localHostname):8080/sse")!

    @Test("SSE Configuration")
    func testSSEConfiguration() async {
        let url = Self.mcpServerURL
        let sseConfig = MCPServerSseConfig(url: url)
        let config = MCPServerConfig.sse(config: sseConfig)
        let proxy = MCPServerProxy(config: config)

        let proxyConfig = await proxy.config
        let cacheToolsList = await proxy.cacheToolsList

        #expect(proxyConfig == config)
        #expect(!cacheToolsList)

        if case .sse(let configuredConfig) = proxyConfig {
            #expect(configuredConfig.url == url)
            #expect(configuredConfig.headers == [:])
        } else {
            Issue.record("Expected SSE configuration")
        }
    }

    @Test("SSE Configuration With Caching")
    func testSSEConfigurationWithCaching() async {
        let url = Self.mcpServerURL
        let sseConfig = MCPServerSseConfig(url: url, headers: ["Authorization": "Bearer token"])
        let config = MCPServerConfig.sse(config: sseConfig)
        let proxy = MCPServerProxy(config: config, cacheToolsList: true)

        let proxyConfig = await proxy.config
        let cacheToolsList = await proxy.cacheToolsList

        #expect(proxyConfig == config)
        #expect(cacheToolsList)

        if case .sse(let configuredConfig) = proxyConfig {
            #expect(configuredConfig.url == url)
            #expect(configuredConfig.headers == ["Authorization": "Bearer token"])
        } else {
            Issue.record("Expected SSE configuration")
        }
    }

    @Test("STDIO Configuration")
    func testStdioConfiguration() async {
        let stdioConfig = MCPServerStdioConfig(
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-filesystem"],
            workingDirectory: "/tmp",
            environment: ["NODE_ENV": "development"]
        )
        let config = MCPServerConfig.stdio(config: stdioConfig)
        let proxy = MCPServerProxy(config: config)

        let proxyConfig = await proxy.config
        let cacheToolsList = await proxy.cacheToolsList

        #expect(proxyConfig == config)
        #expect(!cacheToolsList)

        if case .stdio(let configuredConfig) = proxyConfig {
            #expect(configuredConfig.command == "npx")
            #expect(configuredConfig.args == ["-y", "@modelcontextprotocol/server-filesystem"])
            #expect(configuredConfig.workingDirectory == "/tmp")
            #expect(configuredConfig.environment == ["NODE_ENV": "development"])
        } else {
            Issue.record("Expected stdio configuration")
        }
    }

    @Test("SSE Connect", .enabled(if: isMCPServerAvailable(url: mcpServerURL)))
    func testConnect() async throws {
        let url = Self.mcpServerURL
        let sseConfig = MCPServerSseConfig(url: url)
        let config = MCPServerConfig.sse(config: sseConfig)
        let proxy = MCPServerProxy(config: config)
        try await proxy.connect()
        let name = await proxy.serverName
        let _ = try #require(name, "Expected MCP server name after connect")
        await proxy.disconnect()
    }

    @Test("Ping", .enabled(if: isMCPServerAvailable(url: mcpServerURL)))
    func testPing() async throws {
        let url = Self.mcpServerURL
        let sseConfig = MCPServerSseConfig(url: url)
        let config = MCPServerConfig.sse(config: sseConfig)
        let proxy = MCPServerProxy(config: config)
        try await proxy.connect()
        try await proxy.ping()
        await proxy.disconnect()
    }

    @Test("List Tools", .enabled(if: isMCPServerAvailable(url: mcpServerURL)))
    func testListTools() async throws {
        let url = Self.mcpServerURL
        let sseConfig = MCPServerSseConfig(url: url)
        let config = MCPServerConfig.sse(config: sseConfig)
        let proxy = MCPServerProxy(config: config, cacheToolsList: true)
        try await proxy.connect()

        do {
            let tools = try await proxy.listTools()
            #expect(!tools.isEmpty)
            for tool in tools {
                #expect(!tool.name.isEmpty)
                if case .object(_) = tool.inputSchema {
                } else {
                    Issue.record("Tool schema should be an object type")
                }
            }
            let cachedTools = try await proxy.listTools()
            #expect(tools.count == cachedTools.count)
            for (index, tool) in tools.enumerated() {
                let cachedTool = cachedTools[index]
                #expect(tool.name == cachedTool.name)
                #expect(tool.description == cachedTool.description)
            }
        } catch {
            Issue.record("Failed to list tools: \(error)")
        }
        await proxy.disconnect()
    }

    @Test("Call Tool Whoami", .enabled(if: isMCPServerAvailable(url: mcpServerURL)))
    func testCallToolWhoami() async throws {
        let url = Self.mcpServerURL
        let sseConfig = MCPServerSseConfig(url: url)
        let config = MCPServerConfig.sse(config: sseConfig)
        let proxy = MCPServerProxy(config: config)
        try await proxy.connect()
        let tools = try await proxy.listTools()
        #expect(!tools.isEmpty)
        if tools.contains(where: { $0.name == "whoami" }) {
            let result = try await proxy.callTool("whoami", arguments: [:])
            #expect(!result.isEmpty)
        }

        await proxy.disconnect()
    }

    @Test("STDIO Connect to SwiftMCP Server", .enabled(if: isSwiftMCPDemoExecutableAvailable()))
    func testStdioConnectToSwiftMCPServer() async throws {
        guard let demoExecutable = swiftMCPDemoExecutablePath() else {
            Issue.record("SwiftMCPDemo executable not found")
            return
        }
        let repoPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path
        let stdioConfig = MCPServerStdioConfig(
            command: demoExecutable,
            args: ["stdio"],
            workingDirectory: repoPath,
            environment: [:]
        )
        let config = MCPServerConfig.stdio(config: stdioConfig)
        let proxy = MCPServerProxy(config: config)
        try await proxy.connect()
        let tools = try await proxy.listTools()
        #expect(!tools.isEmpty)
        try await proxy.ping()

        if tools.contains(where: { $0.name == "getCurrentDateTime" }) {
            let result = try await proxy.callTool("getCurrentDateTime")
            let _ = try #require(result.isEmpty == false, "Expected non-empty result from getCurrentDateTime")

            let isoFormatter = ISO8601DateFormatter()
            let date = isoFormatter.date(from: result)
            let _ = try #require(date, "Result should be a valid ISO 8601 date: \(result)")
        }

        await proxy.disconnect()
    }
}

func isMCPServerAvailable(url: URL) -> Bool {
    var request = URLRequest(url: url)
    request.httpMethod = "HEAD"
    let session = URLSession(configuration: .ephemeral)
    let semaphore = DispatchSemaphore(value: 0)
    let availability = AvailabilityFlag(false)

    let task = session.dataTask(with: request) { _, response, _ in
        if let httpResponse = response as? HTTPURLResponse {
            availability.set((200...499).contains(httpResponse.statusCode))
        }
        semaphore.signal()
    }
    task.resume()
    _ = semaphore.wait(timeout: .now() + 2)
    return availability.get()
}

func isSwiftMCPDemoExecutableAvailable() -> Bool {
    return swiftMCPDemoExecutablePath() != nil
}

private func swiftMCPDemoExecutablePath() -> String? {
    let repoPath = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let buildRoot = repoPath.appendingPathComponent(".build")
    let defaultPath = buildRoot.appendingPathComponent("debug/SwiftMCPDemo").path
    if FileManager.default.fileExists(atPath: defaultPath) {
        return defaultPath
    }
    let archPath = buildRoot.appendingPathComponent("arm64-apple-macosx/debug/SwiftMCPDemo").path
    if FileManager.default.fileExists(atPath: archPath) {
        return archPath
    }
    if let enumerator = FileManager.default.enumerator(at: buildRoot, includingPropertiesForKeys: nil) {
        for case let fileURL as URL in enumerator {
            if fileURL.lastPathComponent == "SwiftMCPDemo",
               fileURL.path.contains("/debug/") {
                return fileURL.path
            }
        }
    }
    return nil
}

private final class AvailabilityFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Bool

    init(_ value: Bool) {
        self.value = value
    }

    func set(_ newValue: Bool) {
        lock.lock()
        value = newValue
        lock.unlock()
    }

    func get() -> Bool {
        lock.lock()
        let current = value
        lock.unlock()
        return current
    }
}
