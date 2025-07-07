import Foundation

/// A protocol that provides a default implementation of the MCPLoggingProviding protocol.
///
/// This protocol can be used by servers that want to add logging capabilities without
/// implementing the full protocol themselves. It handles:
/// - Minimum log level management
/// - Sending log messages to all connected clients
/// - Filtering messages based on the minimum log level
///
/// Usage:
/// ```swift
/// @MCPServer
/// actor MyServer: MCPLoggingMixin {
///     // Your server implementation
/// }
/// ```
public protocol MCPLoggingMixin: MCPLoggingProviding {
    /// The current minimum log level for sending messages to clients.
    /// Only messages with this level or higher will be sent.
    nonisolated var minimumLogLevel: LogLevel { get set }
}

// MARK: - Default Implementation

public extension MCPLoggingMixin {
    /// Default implementation for setting the minimum log level.
    /// - Parameter level: The new minimum log level
    mutating func setMinimumLogLevel(_ level: LogLevel) {
        minimumLogLevel = level
    }
    
    /// Default implementation for sending a log message to all connected clients.
    /// - Parameter message: The log message to send
    func sendLog(_ message: LogMessage) async {
        // Only send messages that meet the minimum level requirement
        guard message.level.isAtLeast(minimumLogLevel) else {
            return
        }
        
        // Send to the current session if available
        if let session = Session.current {
            await session.sendLogNotification(message)
        }
        
        // For HTTP+SSE transport, try to broadcast to all connected clients
        if let session = Session.current,
           let transport = session.transport as? HTTPSSETransport {
            await transport.broadcastLog(message)
        }
    }
} 