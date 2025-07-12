import Foundation
import Testing
@testable import SwiftMCP
import Logging

/// Simple transport to record sent JSON-RPC messages.
final class RecordingTransportForNotifications: Transport {
    let server: MCPServer
    var sentMessages: [JSONRPCMessage] = []
    var logger = Logger(label: "RecordingTransport")

    init(server: MCPServer) { self.server = server }
    func start() async throws {}
    func run() async throws {}
    func stop() async throws {}
    func send(_ data: Data) async throws {
        if let message = try? JSONDecoder().decode(JSONRPCMessage.self, from: data) {
            sentMessages.append(message)
        }
    }
}

@Test("Tool list changed notification is sent")
func testToolListChangedNotification() async throws {
    let server = Calculator()
    let transport = RecordingTransportForNotifications(server: server)
    let session = Session(id: UUID())
    session.transport = transport

    let message = JSONRPCMessage.notification(method: "dummy")
    await session.work { _ in
        let context = RequestContext(message: message)
        await context.work { ctx in
            await ctx.sendToolListChanged()
        }
    }

    #expect(transport.sentMessages.count == 1)
    guard case .notification(let data) = transport.sentMessages[0] else {
        throw TestError("Expected notification")
    }
    #expect(data.method == "notifications/tools/list_changed")
}

@Test("Resource list changed notification is sent")
func testResourceListChangedNotification() async throws {
    let server = Calculator()
    let transport = RecordingTransportForNotifications(server: server)
    let session = Session(id: UUID())
    session.transport = transport

    let message = JSONRPCMessage.notification(method: "dummy")
    await session.work { _ in
        let context = RequestContext(message: message)
        await context.work { ctx in
            await ctx.sendResourceListChanged()
        }
    }

    #expect(transport.sentMessages.count == 1)
    guard case .notification(let data) = transport.sentMessages[0] else {
        throw TestError("Expected notification")
    }
    #expect(data.method == "notifications/resources/list_changed")
}

@Test("Prompt list changed notification is sent")
func testPromptListChangedNotification() async throws {
    let server = Calculator()
    let transport = RecordingTransportForNotifications(server: server)
    let session = Session(id: UUID())
    session.transport = transport

    let message = JSONRPCMessage.notification(method: "dummy")
    await session.work { _ in
        let context = RequestContext(message: message)
        await context.work { ctx in
            await ctx.sendPromptListChanged()
        }
    }

    #expect(transport.sentMessages.count == 1)
    guard case .notification(let data) = transport.sentMessages[0] else {
        throw TestError("Expected notification")
    }
    #expect(data.method == "notifications/prompts/list_changed")
}
