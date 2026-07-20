import Foundation
import SwiftMCP

enum IntentsDemoServerFactory {
    // `& Sendable` so the commands can hand the server to
    // `MCPServer.serve(over:)`, which requires `Self: Sendable`.
    static func makeServer() -> (any MCPServer & Sendable)? {
#if canImport(AppIntents)
        if #available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *) {
            return IntentsDemoServer()
        }
#endif
        return nil
    }

    static var unavailableReason: String {
#if canImport(AppIntents)
        return "AppIntents requires macOS 13 / iOS 16 / tvOS 16 / watchOS 9"
#else
        return "AppIntents framework unavailable"
#endif
    }
}
