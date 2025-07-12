import Foundation
@preconcurrency import AnyCodable

/// Represents a log message as defined in the MCP protocol specification.
public struct LogMessage: Codable, Sendable {
    /// The severity level of the log message
    public let level: LogLevel
    
    /// Optional logger name/category for the log message
    public let logger: String?
    
    /// The log message data (can be any JSON-serializable object)
    public let data: AnyCodable
    
    /// Creates a new log message
    /// - Parameters:
    ///   - level: The severity level of the log message
    ///   - logger: Optional logger name/category
    ///   - data: The log message data
    public init(level: LogLevel, logger: String? = nil, data: AnyCodable) {
        self.level = level
        self.logger = logger
        self.data = data
    }
    
    /// Creates a log message with a simple string message
    /// - Parameters:
    ///   - level: The severity level of the log message
    ///   - message: The log message text
    ///   - logger: Optional logger name/category
    public init(level: LogLevel, message: String, logger: String? = nil) {
        self.level = level
        self.logger = logger
        self.data = AnyCodable(message)
    }
    
    /// Creates a log message with a dictionary of data
    /// - Parameters:
    ///   - level: The severity level of the log message
    ///   - data: Dictionary of log data
    ///   - logger: Optional logger name/category
    public init(level: LogLevel, data: [String: Any], logger: String? = nil) {
        self.level = level
        self.logger = logger
        self.data = AnyCodable(data)
    }
} 