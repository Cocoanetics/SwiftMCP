import Foundation
import AnyCodable
import Testing
@testable import SwiftMCP

@Suite("Proxy Log Notification Tests")
struct ProxyLogNotificationTests {
    @Test("Proxy forwards log notifications to handler")
    func proxyHandlesLogNotifications() async {
        let proxy = MCPServerProxy(
            config: .sse(config: MCPServerSseConfig(url: URL(string: "http://localhost")!, headers: [:]))
        )
        let capture = LogCapture()
        await proxy.setLogNotificationHandler(capture)

        let params: [String: AnyCodable] = [
            "level": AnyCodable("warning"),
            "logger": AnyCodable("demo"),
            "data": AnyCodable("hello")
        ]
        let notification = JSONRPCMessage.JSONRPCNotificationData(
            method: "notifications/message",
            params: params
        )

        await proxy.handleLogNotification(notification)

        let messages = await capture.messages
        #expect(messages.count == 1)
        let message = messages[0]
        #expect(message.level == .warning)
        #expect(message.logger == "demo")
        #expect(message.data.value as? String == "hello")
    }
}

private actor LogCapture: MCPServerProxyLogNotificationHandling {
    private(set) var messages: [LogMessage] = []

    func mcpServerProxy(_ proxy: MCPServerProxy, didReceiveLog message: LogMessage) async {
        messages.append(message)
    }
}
