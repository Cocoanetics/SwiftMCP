//
//  NoOpLogHandler.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 19.03.25.
//

import Foundation
import Logging

struct NoOpLogHandler: LogHandler {
	var logLevel: Logger.Level = .critical
	var metadata: Logger.Metadata = [:]
	
	subscript(metadataKey key: String) -> Logger.Metadata.Value? {
		get { return nil }
		set { }
	}
	
	func log(level: Logger.Level, message: Logger.Message, metadata: Logger.Metadata?, source: String, file: String, function: String, line: UInt) {
		// Discard all log messages.
	}
}
