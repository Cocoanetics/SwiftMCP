//
//  OSLogHandler.swift
//  SwiftMail
//
//  Created by Oliver Drobnik on 04.03.25.
//

import Foundation
import Logging

#if canImport(OSLog)

@preconcurrency import OSLog

// Custom LogHandler that bridges Swift Logging to OSLog
struct OSLogHandler: LogHandler {
    let label: String
    let log: OSLog
    
    // Required property for LogHandler protocol
    var logLevel: Logging.Logger.Level = .debug  // Set to debug to capture all logs
    
    // Required property for LogHandler protocol
    var metadata = Logging.Logger.Metadata()
    
    // Required subscript for LogHandler protocol
    subscript(metadataKey metadataKey: String) -> Logging.Logger.Metadata.Value? {
        get {
            return metadata[metadataKey]
        }
        set {
            metadata[metadataKey] = newValue
        }
    }
    
    // Initialize with a label and OSLog instance
    init(label: String, log: OSLog) {
        self.label = label
        self.log = log
    }
    
    // Required method for LogHandler protocol
    func log(level: Logging.Logger.Level, message: Logging.Logger.Message, metadata: Logging.Logger.Metadata?, source: String, file: String, function: String, line: UInt) {
        // Map Swift Logging levels to OSLog types
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
        
        // Log the message using OSLog
        os_log("%{public}@", log: log, type: type, message.description)
    }
}

#endif
