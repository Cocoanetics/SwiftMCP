//
//  NoOpLogHandler.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 19.03.25.
//

import Foundation
import Logging

// swiftlint:disable unused_setter_value
// `LogHandler` protocol from swift-log dictates the signatures; we just no-op.
struct NoOpLogHandler: LogHandler {
	var logLevel: Logger.Level = .critical
	var metadata: Logger.Metadata = [:]

	subscript(metadataKey key: String) -> Logger.Metadata.Value? {
		get { return nil }
		set { }
	}

	func log(event: LogEvent) {
		// Discard all log messages.
	}
}
// swiftlint:enable unused_setter_value
