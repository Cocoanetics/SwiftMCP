import Foundation
import Logging

#if canImport(OSLog)
import OSLog

extension LoggingSystem {
    /// Bootstrap the logging system with OSLog on Apple platforms
    /// - Parameters:
    ///   - subsystem: The subsystem identifier for OSLog
    ///   - logLevel: The default log level to use (default: .info)
    static func bootstrapWithOSLog(subsystem: String = "com.cocoanetics.SwiftMCP",
								   logLevel: Logging.Logger.Level = ProcessInfo.processInfo.environment["ENABLE_DEBUG_OUTPUT"] == "1" ? .trace : .info) {
        bootstrap { label in
            // Create an OSLog-based logger
            let category = label.split(separator: ".").last?.description ?? "default"
            let osLogger = OSLog(subsystem: subsystem, category: category)
            
            // Set log level based on parameter
            var handler = OSLogHandler(label: label, log: osLogger)
            handler.logLevel = logLevel
            
            return handler
        }
    }
}
#endif 
