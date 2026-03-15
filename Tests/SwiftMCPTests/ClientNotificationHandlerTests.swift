import Foundation
import Testing
@testable import SwiftMCP

// MARK: - Test Handler Implementations

private final class MockResourceHandler: MCPServerProxyResourceNotificationHandling, @unchecked Sendable {
    var updatedURIs: [URL] = []

    func mcpServerProxy(_ proxy: MCPServerProxy, resourceUpdatedAt uri: URL) async {
        updatedURIs.append(uri)
    }
}

private final class MockToolsListChangedHandler: MCPServerProxyToolsListChangedHandling, @unchecked Sendable {
    var callCount = 0

    func mcpServerProxyToolsListDidChange(_ proxy: MCPServerProxy) async {
        callCount += 1
    }
}

private final class MockResourcesListChangedHandler: MCPServerProxyResourcesListChangedHandling, @unchecked Sendable {
    var callCount = 0

    func mcpServerProxyResourcesListDidChange(_ proxy: MCPServerProxy) async {
        callCount += 1
    }
}

private final class MockPromptsListChangedHandler: MCPServerProxyPromptsListChangedHandling, @unchecked Sendable {
    var callCount = 0

    func mcpServerProxyPromptsListDidChange(_ proxy: MCPServerProxy) async {
        callCount += 1
    }
}

// MARK: - Helper

/// Creates a proxy without connecting — sufficient for handler installation tests.
private func makeProxy() -> MCPServerProxy {
    let config = MCPServerConfig.stdio(config: MCPServerStdioConfig(
        command: "/bin/echo",
        args: [],
        workingDirectory: "/tmp",
        environment: [:]
    ))
    return MCPServerProxy(config: config)
}

@Suite("Client Notification Handler Tests")
struct ClientNotificationHandlerTests {

    // MARK: - Handler Installation

    @Test("Resource handler can be set and cleared")
    func resourceHandlerSetAndClear() async {
        let proxy = makeProxy()
        let handler = MockResourceHandler()

        await proxy.setResourceNotificationHandler(handler)
        let installed = await proxy.resourceNotificationHandler
        #expect(installed != nil)

        await proxy.setResourceNotificationHandler(nil)
        let cleared = await proxy.resourceNotificationHandler
        #expect(cleared == nil)
    }

    @Test("Tools list changed handler can be set and cleared")
    func toolsListChangedHandlerSetAndClear() async {
        let proxy = makeProxy()
        let handler = MockToolsListChangedHandler()

        await proxy.setToolsListChangedHandler(handler)
        let installed = await proxy.toolsListChangedHandler
        #expect(installed != nil)

        await proxy.setToolsListChangedHandler(nil)
        let cleared = await proxy.toolsListChangedHandler
        #expect(cleared == nil)
    }

    @Test("Resources list changed handler can be set and cleared")
    func resourcesListChangedHandlerSetAndClear() async {
        let proxy = makeProxy()
        let handler = MockResourcesListChangedHandler()

        await proxy.setResourcesListChangedHandler(handler)
        let installed = await proxy.resourcesListChangedHandler
        #expect(installed != nil)

        await proxy.setResourcesListChangedHandler(nil)
        let cleared = await proxy.resourcesListChangedHandler
        #expect(cleared == nil)
    }

    @Test("Prompts list changed handler can be set and cleared")
    func promptsListChangedHandlerSetAndClear() async {
        let proxy = makeProxy()
        let handler = MockPromptsListChangedHandler()

        await proxy.setPromptsListChangedHandler(handler)
        let installed = await proxy.promptsListChangedHandler
        #expect(installed != nil)

        await proxy.setPromptsListChangedHandler(nil)
        let cleared = await proxy.promptsListChangedHandler
        #expect(cleared == nil)
    }
}
