import Foundation
import Testing
import Logging
@testable import SwiftMCP

/// A simple test server that implements logging
@MCPServer(name: "Test Logging Server")
class TestLoggingServer: MCPLoggingProviding {
    var minimumLogLevel: LogLevel = .info
    
    func setMinimumLogLevel(_ level: LogLevel) {
        minimumLogLevel = level
    }
    
    func sendLog(_ message: LogMessage) async {
        // Only send messages that meet the minimum level requirement
        guard message.level.isAtLeast(minimumLogLevel) else {
            return
        }
        // For testing, do nothing (was: print log message)
    }
    
    @MCPTool(description: "Test logging functionality with different log levels")
    func testLogging() async {
        await log(.debug, "This is a debug message", logger: "test")
        await log(.info, "This is an info message", logger: "test")
        await log(.warning, "This is a warning message", logger: "test")
        await log(.error, "This is an error message", logger: "test")
    }
}

/// Transport that records the active Session.current while sending.
final class SessionContextRecordingTransport: Transport, @unchecked Sendable {
    let server: MCPServer
    var logger = Logger(label: "SessionContextRecordingTransport")
    var sentMessages: [JSONRPCMessage] = []
    var capturedSessionID: UUID?

    init(server: MCPServer) {
        self.server = server
    }

    func start() async throws {}
    func run() async throws {}
    func stop() async throws {}

    func send(_ data: Data) async throws {
        capturedSessionID = await Session.current?.id
        if let message = try? JSONDecoder().decode(JSONRPCMessage.self, from: data) {
            sentMessages.append(message)
        }
    }
}

@Test
func testLogLevelPriority() throws {
    let debug = LogLevel.debug
    let info = LogLevel.info
    let warning = LogLevel.warning
    let error = LogLevel.error
    
    #expect(debug.priority == 7)
    #expect(info.priority == 6)
    #expect(warning.priority == 4)
    #expect(error.priority == 3)
    
    #expect(debug.isAtLeast(debug))
    #expect(info.isAtLeast(debug))
    #expect(warning.isAtLeast(debug))
    #expect(error.isAtLeast(debug))
    
    #expect(!debug.isAtLeast(info))
    #expect(info.isAtLeast(info))
    #expect(warning.isAtLeast(info))
    #expect(error.isAtLeast(info))
}

@Test
func testLogLevelFromString() throws {
    #expect(LogLevel(string: "debug") == .debug)
    #expect(LogLevel(string: "info") == .info)
    #expect(LogLevel(string: "warning") == .warning)
    #expect(LogLevel(string: "error") == .error)
    #expect(LogLevel(string: "critical") == .critical)
    #expect(LogLevel(string: "alert") == .alert)
    #expect(LogLevel(string: "emergency") == .emergency)
    
    #expect(LogLevel(string: "DEBUG") == .debug)
    #expect(LogLevel(string: "INFO") == .info)
    #expect(LogLevel(string: "WARNING") == .warning)
    
    #expect(LogLevel(string: "invalid") == nil)
    #expect(LogLevel(string: "unknown") == nil)
}

@Test
func testLogMessageCreation() throws {
    let message1 = LogMessage(level: .info, message: "Test message")
    #expect(message1.level == .info)
    #expect(message1.logger == nil)
    #expect(message1.data.value as? String == "Test message")
    
    let message2 = LogMessage(level: .error, message: "Error message", logger: "test")
    #expect(message2.level == .error)
    #expect(message2.logger == "test")
    #expect(message2.data.value as? String == "Error message")
    
    let data: [String: Any] = ["key": "value", "number": 42]
    let message3 = LogMessage(level: .debug, data: data, logger: "debug")
    #expect(message3.level == .debug)
    #expect(message3.logger == "debug")
    let messageData = message3.data.value as? [String: Any]
    #expect(messageData != nil)
    #expect(messageData?["key"] as? String == "value")
    #expect(messageData?["number"] as? Int == 42)
}

@Test
func testLoggingServer() async throws {
    let server = TestLoggingServer()
    
    // Test with default level (info)
    await server.testLogging()
    
    // Test with debug level
    server.setMinimumLogLevel(.debug)
    await server.testLogging()
    
    // Test with error level
    server.setMinimumLogLevel(.error)
    await server.testLogging()
}

@Test
func testSendLogNotificationBindsSessionContext() async throws {
    let server = TestLoggingServer()
    let transport = SessionContextRecordingTransport(server: server)
    let session = Session(id: UUID())
    let expectedSessionID = await session.id
    await session.setTransport(transport)

    await session.sendLogNotification(LogMessage(level: .info, message: "hello", logger: "test"))

    #expect(transport.sentMessages.count == 1)
    #expect(transport.capturedSessionID == expectedSessionID)

    if case let .notification(notificationData) = transport.sentMessages[0] {
        #expect(notificationData.method == "notifications/message")
    } else {
        #expect(Bool(false))
    }
}
