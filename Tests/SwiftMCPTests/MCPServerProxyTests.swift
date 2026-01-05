import Testing
import SwiftMCP
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct MCPServerProxyTests {
    static let mcpServerURL = URL(string: "http://\(String.localHostname):8080/sse")!

    init() {
        TestLoggingBootstrap.install()
    }

    @Test("Proxy config: SSE")
    func testSSEConfiguration() async {
        let url = Self.mcpServerURL
        let sseConfig = MCPServerSseConfig(url: url)
        let config = MCPServerConfig.sse(config: sseConfig)
        let proxy = MCPServerProxy(config: config)

        let proxyConfig = await proxy.config
        let cacheToolsList = await proxy.cacheToolsList

        #expect(!cacheToolsList)

        if case .sse(let configuredConfig) = proxyConfig {
            #expect(configuredConfig == sseConfig)
            #expect(configuredConfig.url == url)
            #expect(configuredConfig.headers == [:])
        } else {
            Issue.record("Expected SSE configuration")
        }
    }

    @Test("Proxy config: SSE with caching")
    func testSSEConfigurationWithCaching() async {
        let url = Self.mcpServerURL
        let sseConfig = MCPServerSseConfig(url: url, headers: ["Authorization": "Bearer token"])
        let config = MCPServerConfig.sse(config: sseConfig)
        let proxy = MCPServerProxy(config: config, cacheToolsList: true)

        let proxyConfig = await proxy.config
        let cacheToolsList = await proxy.cacheToolsList

        #expect(cacheToolsList)

        if case .sse(let configuredConfig) = proxyConfig {
            #expect(configuredConfig == sseConfig)
            #expect(configuredConfig.url == url)
            #expect(configuredConfig.headers == ["Authorization": "Bearer token"])
        } else {
            Issue.record("Expected SSE configuration")
        }
    }

    @Test("Proxy config: STDIO")
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

        #expect(!cacheToolsList)

        if case .stdio(let configuredConfig) = proxyConfig {
            #expect(configuredConfig == stdioConfig)
            #expect(configuredConfig.command == "npx")
            #expect(configuredConfig.args == ["-y", "@modelcontextprotocol/server-filesystem"])
            #expect(configuredConfig.workingDirectory == "/tmp")
            #expect(configuredConfig.environment == ["NODE_ENV": "development"])
        } else {
            Issue.record("Expected stdio configuration")
        }
    }

    @Test("SSE live: connect", .enabled(if: isMCPServerAvailable(url: mcpServerURL)))
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

    @Test("SSE live: ping", .enabled(if: isMCPServerAvailable(url: mcpServerURL)))
    func testPing() async throws {
        let url = Self.mcpServerURL
        let sseConfig = MCPServerSseConfig(url: url)
        let config = MCPServerConfig.sse(config: sseConfig)
        let proxy = MCPServerProxy(config: config)
        try await proxy.connect()
        try await proxy.ping()
        await proxy.disconnect()
    }

    @Test("SSE live: list tools", .enabled(if: isMCPServerAvailable(url: mcpServerURL)))
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
                if case .object(_, _) = tool.inputSchema {
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

    @Test("SSE live: call greet", .enabled(if: isMCPServerAvailable(url: mcpServerURL)))
    func testCallToolGreet() async throws {
        let url = Self.mcpServerURL
        let sseConfig = MCPServerSseConfig(url: url)
        let config = MCPServerConfig.sse(config: sseConfig)
        let proxy = MCPServerProxy(config: config)
        try await proxy.connect()
        let tools = try await proxy.listTools()
        #expect(!tools.isEmpty)
        if tools.contains(where: { $0.name == "greet" }) {
            let result = try await proxy.callTool("greet", arguments: ["name": "Oliver"])
            #expect(!result.isEmpty)
        }

        await proxy.disconnect()
    }

    @Test("STDIO in-process: connect")
    func testStdioConnectToSwiftMCPServer() async throws {
        let server = LocalStdioServer()
        let config = MCPServerConfig.stdioHandles(server: server)
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

    @Test("STDIO in-process: tool resource content")
    func testStdioToolResourceContent() async throws {
        let server = LocalStdioServer()
        let config = MCPServerConfig.stdioHandles(server: server)
        let proxy = MCPServerProxy(config: config)
        try await proxy.connect()

        let imageResult = try await proxy.callTool("sampleImageResource")
        let imagePayload = try JSONDecoder().decode(ToolBinaryContent.self, from: Data(imageResult.utf8))
        #expect(imagePayload.type == "image")
        #expect(imagePayload.mimeType == "image/png")
        let decodedImage = try #require(Data(base64Encoded: imagePayload.data), "Expected image data to be base64")
        #expect(decodedImage == LocalStdioServer.sampleImageData)

        let audioResult = try await proxy.callTool("sampleAudioResource")
        let audioPayload = try JSONDecoder().decode(ToolBinaryContent.self, from: Data(audioResult.utf8))
        #expect(audioPayload.type == "audio")
        #expect(audioPayload.mimeType == "audio/wav")
        let decodedAudio = try #require(Data(base64Encoded: audioPayload.data), "Expected audio data to be base64")
        #expect(decodedAudio == LocalStdioServer.sampleAudioData)

        await proxy.disconnect()
    }

    @Test("STDIO external: local build", .enabled(if: isLocalSwiftMCPDemoAvailable()))
    func testStdioConnectToLocalBuild() async throws {
        guard let demoExecutable = localSwiftMCPDemoExecutable() else {
            Issue.record("SwiftMCPDemo executable not found")
            return
        }
        let stdioConfig = MCPServerStdioConfig(
            command: demoExecutable,
            args: ["stdio"],
            workingDirectory: repositoryRootPath(),
            environment: [:]
        )
        let config = MCPServerConfig.stdio(config: stdioConfig)
        let proxy = MCPServerProxy(config: config)
        try await proxy.connect()
        let tools = try await proxy.listTools()
        #expect(!tools.isEmpty)
        try await proxy.ping()
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

private func repositoryRootPath() -> String {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .path
}

private func isLocalSwiftMCPDemoAvailable() -> Bool {
    localSwiftMCPDemoExecutable() != nil
}

private func localSwiftMCPDemoExecutable() -> String? {
    let repoPath = repositoryRootPath()
    let debugPath = "\(repoPath)/.build/arm64-apple-macosx/debug/SwiftMCPDemo"
    if FileManager.default.isExecutableFile(atPath: debugPath) {
        return debugPath
    }
    let releasePath = "\(repoPath)/.build/arm64-apple-macosx/release/SwiftMCPDemo"
    if FileManager.default.isExecutableFile(atPath: releasePath) {
        return releasePath
    }
    return nil
}

@MCPServer(name: "SwiftMCP Test Server")
final class LocalStdioServer: Sendable {
    static let sampleImageData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    static let sampleAudioData = Data([0x52, 0x49, 0x46, 0x46, 0x24, 0x80, 0x00, 0x00])

    /// Returns the current time in ISO 8601 format.
    @MCPTool
    func getCurrentDateTime() -> String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: Date())
    }

    @MCPTool(description: "Returns a sample PNG payload as resource content.")
    func sampleImageResource() -> GenericResourceContent {
        let uri = URL(string: "file:///tmp/sample.png")!
        return GenericResourceContent(uri: uri, mimeType: "image/png", blob: Self.sampleImageData)
    }

    @MCPTool(description: "Returns a sample WAV payload as resource content.")
    func sampleAudioResource() -> GenericResourceContent {
        let uri = URL(string: "file:///tmp/sample.wav")!
        return GenericResourceContent(uri: uri, mimeType: "audio/wav", blob: Self.sampleAudioData)
    }
}

private struct ToolBinaryContent: Decodable {
    let type: String
    let data: String
    let mimeType: String
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
