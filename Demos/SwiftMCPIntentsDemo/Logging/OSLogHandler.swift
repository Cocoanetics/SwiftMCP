import Foundation
import Logging

#if canImport(OSLog)
@preconcurrency import OSLog

/// LogHandler that bridges Swift Logging to OSLog.
struct OSLogHandler: LogHandler {
    let label: String
    let log: OSLog
    
    var logLevel: Logging.Logger.Level = .debug
    var metadata = Logging.Logger.Metadata()
    
    subscript(metadataKey metadataKey: String) -> Logging.Logger.Metadata.Value? {
        get { metadata[metadataKey] }
        set { metadata[metadataKey] = newValue }
    }
    
    init(label: String, log: OSLog) {
        self.label = label
        self.log = log
    }
    
    func log(level: Logging.Logger.Level, message: Logging.Logger.Message, metadata: Logging.Logger.Metadata?, source: String, file: String, function: String, line: UInt) {
        let type: OSLogType
        switch level {
        case .trace, .debug:
            type = .debug
        case .info, .notice:
            type = .info
        case .warning:
            type = .default
        case .error:
            type = .error
        case .critical:
            type = .fault
        }
        
        os_log("%{public}@", log: log, type: type, message.description)
    }
}
#endif

