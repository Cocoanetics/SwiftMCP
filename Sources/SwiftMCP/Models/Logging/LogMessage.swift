import Foundation

/// Represents a log message as defined in the MCP protocol specification.
public struct LogMessage: Codable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case level
        case logger
        case data
    }

    /// The severity level of the log message
    public let level: LogLevel

    /// Optional logger name/category for the log message
    public let logger: String?

    /// The log message data (can be any JSON-serializable object)
    public let data: JSONValue

    /// Creates a new log message
    /// - Parameters:
    ///   - level: The severity level of the log message
    ///   - logger: Optional logger name/category
    ///   - data: The log message data
    public init(level: LogLevel, logger: String? = nil, data: JSONValue) {
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
        self.data = .string(message)
    }

    /// Creates a log message with a dictionary of data
    /// - Parameters:
    ///   - level: The severity level of the log message
    ///   - data: Dictionary of log data
    ///   - logger: Optional logger name/category
    public init(level: LogLevel, data: JSONDictionary, logger: String? = nil) {
        self.level = level
        self.logger = logger
        self.data = .object(data)
    }

    public init(level: LogLevel, data: [String: Any], logger: String? = nil) {
        self.level = level
        self.logger = logger
        self.data = .object((try? data.mapValues { try JSONValue(jsonObject: $0) }) ?? [:])
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawLevel = (try? container.decode(String.self, forKey: .level)) ?? LogLevel.info.rawValue

        level = LogLevel(string: rawLevel) ?? .info
        logger = try? container.decode(String.self, forKey: .logger)
        data = (try? container.decode(JSONValue.self, forKey: .data)) ?? .string("")
    }
}
