import Foundation
import Testing
@testable import SwiftMCP

@Suite("Proxy Notification Handler Tests")
struct ProxyNotificationHandlerTests {
    @Test("Proxy forwards custom typed notifications to handler")
    func proxyHandlesCustomNotifications() async {
        let proxy = makeProxy()
        let capture = RunStatusCapture()

        await proxy.setNotificationHandler("notifications/runStatusChanged", as: RunStatusUpdate.self) { update in
            await capture.record(update)
        }

        let notification = JSONRPCMessage.JSONRPCNotificationData(
            method: "notifications/runStatusChanged",
            params: [
                "runID": "run-123",
                "status": "completed",
                "step": 3
            ]
        )

        await proxy.handleNotification(notification)

        let updates = await capture.updates
        #expect(updates.count == 1)
        #expect(updates[0].runID == "run-123")
        #expect(updates[0].status == "completed")
        #expect(updates[0].step == 3)
    }

    @Test("Proxy forwards log notifications to handler")
    func proxyHandlesLogNotifications() async {
        let proxy = makeProxy()
        let capture = LogCapture()
        await proxy.setLogNotificationHandler(capture)

        let notification = JSONRPCMessage.JSONRPCNotificationData(
            method: "notifications/message",
            params: [
                "level": "warning",
                "logger": "demo",
                "data": "hello"
            ]
        )

        await proxy.handleNotification(notification)

        let messages = await capture.messages
        #expect(messages.count == 1)
        let message = messages[0]
        #expect(message.level == .warning)
        #expect(message.logger == "demo")
        #expect(message.data.value as? String == "hello")
    }

    @Test("Proxy tolerates malformed optional log fields and still forwards handler callbacks")
    func proxyHandlesMalformedLogNotifications() async {
        let proxy = makeProxy()
        let capture = LogCapture()
        await proxy.setLogNotificationHandler(capture)

        let notification = JSONRPCMessage.JSONRPCNotificationData(
            method: "notifications/message",
            params: [
                "level": 3,
                "logger": .object(["name": "demo"]),
                "data": "hello"
            ]
        )

        await proxy.handleNotification(notification)

        let messages = await capture.messages
        #expect(messages.count == 1)
        let message = messages[0]
        #expect(message.level == .info)
        #expect(message.logger == nil)
        #expect(message.data.value as? String == "hello")
    }

    @Test("Proxy forwards progress notifications to handler")
    func proxyHandlesProgressNotifications() async {
        let proxy = makeProxy()
        let capture = ProgressCapture()
        await proxy.setProgressNotificationHandler(capture)

        let notification = JSONRPCMessage.JSONRPCNotificationData(
            method: "notifications/progress",
            params: [
                "progressToken": "job-42",
                "progress": 0.5,
                "total": 1.0,
                "message": "Halfway there"
            ]
        )

        await proxy.handleNotification(notification)

        let notifications = await capture.notifications
        #expect(notifications.count == 1)
        let progress = notifications[0]
        #expect(progress.progressToken.value as? String == "job-42")
        #expect(progress.progress == 0.5)
        #expect(progress.total == 1.0)
        #expect(progress.message == "Halfway there")
    }

    private func makeProxy() -> MCPServerProxy {
        MCPServerProxy(
            config: .sse(config: MCPServerSseConfig(url: URL(string: "http://localhost")!, headers: [:]))
        )
    }
}

private struct RunStatusUpdate: Codable, Sendable {
    let runID: String
    let status: String
    let step: Int
}

private actor RunStatusCapture {
    private(set) var updates: [RunStatusUpdate] = []

    func record(_ update: RunStatusUpdate) {
        updates.append(update)
    }
}

private actor LogCapture: MCPServerProxyLogNotificationHandling {
    private(set) var messages: [LogMessage] = []

    func mcpServerProxy(_ proxy: MCPServerProxy, didReceiveLog message: LogMessage) async {
        messages.append(message)
    }
}

private actor ProgressCapture: MCPServerProxyProgressNotificationHandling {
    private(set) var notifications: [ProgressNotification] = []

    func mcpServerProxy(_ proxy: MCPServerProxy, didReceiveProgress progress: ProgressNotification) async {
        notifications.append(progress)
    }
}
