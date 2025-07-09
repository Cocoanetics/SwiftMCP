import Foundation
import Testing
@testable import SwiftMCP
import Logging
import AnyCodable

/// Simple transport that records JSON-RPC messages sent through it.
final class RecordingTransport: Transport, @unchecked Sendable {
    let server: MCPServer
    var sentMessages: [JSONRPCMessage] = []
    var logger = Logger(label: "RecordingTransport")

    init(server: MCPServer) {
        self.server = server
    }

    func start() async throws {}
    func run() async throws {}
    func stop() async throws {}

    func send(_ data: Data) async throws {
        if let message = try? JSONDecoder().decode(JSONRPCMessage.self, from: data) {
            sentMessages.append(message)
        }
    }
}

@Test("RequestContext extracts progress token")
func testContextProgressToken() throws {
    let message = JSONRPCMessage.request(
        id: 1,
        method: "tools/call",
        params: [
            "name": AnyCodable("getCurrentDateTime"),
            "arguments": AnyCodable([:]),
            "_meta": AnyCodable(["progressToken": 5])
        ]
    )

    let context = RequestContext(message: message)
    #expect(context.id == .int(1))
    #expect(context.method == "tools/call")
    #expect(context.meta?.progressToken?.value as? Int == 5)
}

@Test("Progress notification is sent via session")
func testProgressNotification() async throws {
    let server = Calculator()
    let transport = RecordingTransport(server: server)
    let session = Session(id: UUID())
    await session.setTransport(transport)

    let message = JSONRPCMessage.request(
        id: 2,
        method: "tools/call",
        params: [
            "name": AnyCodable("getCurrentDateTime"),
            "arguments": AnyCodable([:]),
            "_meta": AnyCodable(["progressToken": "abc"])
        ]
    )

    await session.work { _ in
        let context = RequestContext(message: message)
        await context.work { ctx in
            await ctx.reportProgress(0.5, total: 1.0, message: "Halfway")
        }
    }

    #expect(transport.sentMessages.count == 1)
    guard case .notification(let data) = transport.sentMessages[0] else {
        throw TestError("Expected notification")
    }
    #expect(data.method == "notifications/progress")
    let params = try #require(data.params)
    #expect(params["progressToken"]?.value as? String == "abc")
    #expect(params["progress"]?.value as? Double == 0.5)
    #expect(params["total"]?.value as? Int == 1)
    #expect(params["message"]?.value as? String == "Halfway")
}
