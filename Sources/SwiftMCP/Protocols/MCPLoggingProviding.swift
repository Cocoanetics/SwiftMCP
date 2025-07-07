import Foundation

/// Protocol for servers that provide logging capabilities to clients.
///
/// This protocol defines the interface for MCP servers that can send structured
/// log messages to clients. Servers implementing this protocol can:
/// - Send log messages with different severity levels
/// - Configure minimum log levels
/// - Provide categorized logging through logger names
///
/// The logging follows the MCP protocol specification and uses standard syslog
/// severity levels as defined in RFC 5424.
public protocol MCPLoggingProviding: MCPService {
    /// The current minimum log level for sending messages to clients.
    /// Only messages with this level or higher will be sent.
    nonisolated var minimumLogLevel: LogLevel { get }
    
    /// Sets the minimum log level for sending messages to clients.
    /// - Parameter level: The new minimum log level
    func setMinimumLogLevel(_ level: LogLevel)
    
    /// Sends a log message to all connected clients.
    /// - Parameter message: The log message to send
    func sendLog(_ message: LogMessage) async
    
    /// Convenience method to send a log message with a simple string.
    /// - Parameters:
    ///   - level: The severity level of the log message
    ///   - message: The log message text
    ///   - logger: Optional logger name/category
    func log(_ level: LogLevel, _ message: String, logger: String?) async
    
    /// Convenience method to send a debug log message.
    /// - Parameters:
    ///   - message: The log message text
    ///   - logger: Optional logger name/category
    func debug(_ message: String, logger: String?) async
    
    /// Convenience method to send an info log message.
    /// - Parameters:
    ///   - message: The log message text
    ///   - logger: Optional logger name/category
    func info(_ message: String, logger: String?) async
    
    /// Convenience method to send a notice log message.
    /// - Parameters:
    ///   - message: The log message text
    ///   - logger: Optional logger name/category
    func notice(_ message: String, logger: String?) async
    
    /// Convenience method to send a warning log message.
    /// - Parameters:
    ///   - message: The log message text
    ///   - logger: Optional logger name/category
    func warning(_ message: String, logger: String?) async
    
    /// Convenience method to send an error log message.
    /// - Parameters:
    ///   - message: The log message text
    ///   - logger: Optional logger name/category
    func error(_ message: String, logger: String?) async
    
    /// Convenience method to send a critical log message.
    /// - Parameters:
    ///   - message: The log message text
    ///   - logger: Optional logger name/category
    func critical(_ message: String, logger: String?) async
    
    /// Convenience method to send an alert log message.
    /// - Parameters:
    ///   - message: The log message text
    ///   - logger: Optional logger name/category
    func alert(_ message: String, logger: String?) async
    
    /// Convenience method to send an emergency log message.
    /// - Parameters:
    ///   - message: The log message text
    ///   - logger: Optional logger name/category
    func emergency(_ message: String, logger: String?) async
}

// MARK: - Default Implementations

public extension MCPLoggingProviding {
    /// Default implementation for sending a log message with a simple string.
    func log(_ level: LogLevel, _ message: String, logger: String?) async {
        let logMessage = LogMessage(level: level, message: message, logger: logger)
        await sendLog(logMessage)
    }
    
    /// Default implementation for debug logging.
    func debug(_ message: String, logger: String?) async {
        await log(.debug, message, logger: logger)
    }
    
    /// Default implementation for info logging.
    func info(_ message: String, logger: String?) async {
        await log(.info, message, logger: logger)
    }
    
    /// Default implementation for notice logging.
    func notice(_ message: String, logger: String?) async {
        await log(.notice, message, logger: logger)
    }
    
    /// Default implementation for warning logging.
    func warning(_ message: String, logger: String?) async {
        await log(.warning, message, logger: logger)
    }
    
    /// Default implementation for error logging.
    func error(_ message: String, logger: String?) async {
        await log(.error, message, logger: logger)
    }
    
    /// Default implementation for critical logging.
    func critical(_ message: String, logger: String?) async {
        await log(.critical, message, logger: logger)
    }
    
    /// Default implementation for alert logging.
    func alert(_ message: String, logger: String?) async {
        await log(.alert, message, logger: logger)
    }
    
    /// Default implementation for emergency logging.
    func emergency(_ message: String, logger: String?) async {
        await log(.emergency, message, logger: logger)
    }
} 