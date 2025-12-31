import Logging

enum TestLoggingBootstrap {
    private static let once: Void = {
        LoggingSystem.bootstrap { label in
            var handler = StreamLogHandler.standardError(label: label)
            handler.logLevel = .critical
            return handler
        }
    }()

    static func install() {
        _ = once
    }
}
