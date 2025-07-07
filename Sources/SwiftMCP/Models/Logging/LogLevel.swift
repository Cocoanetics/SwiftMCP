import Foundation

/// Represents the log levels as defined in the MCP protocol specification.
/// These follow the standard syslog severity levels specified in RFC 5424.
public enum LogLevel: String, CaseIterable, Codable, Sendable {
    /// Detailed debugging information (function entry/exit points)
    case debug = "debug"
    
    /// General informational messages (operation progress updates)
    case info = "info"
    
    /// Normal but significant events (configuration changes)
    case notice = "notice"
    
    /// Warning conditions (deprecated feature usage)
    case warning = "warning"
    
    /// Error conditions (operation failures)
    case error = "error"
    
    /// Critical conditions (system component failures)
    case critical = "critical"
    
    /// Action must be taken immediately (data corruption detected)
    case alert = "alert"
    
    /// System is unusable (complete system failure)
    case emergency = "emergency"
    
    /// Returns the numeric priority value for this log level (RFC 5424)
    public var priority: Int {
        switch self {
        case .emergency: return 0
        case .alert: return 1
        case .critical: return 2
        case .error: return 3
        case .warning: return 4
        case .notice: return 5
        case .info: return 6
        case .debug: return 7
        }
    }
    
    /// Returns true if this level is at least as severe as the given level
    public func isAtLeast(_ level: LogLevel) -> Bool {
        return self.priority <= level.priority
    }
    
    /// Creates a LogLevel from a string, returning nil if invalid
    public init?(string: String) {
        self.init(rawValue: string.lowercased())
    }
} 