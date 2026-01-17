import Foundation
import SwiftMCP

@MainActor
final class ServerController: ObservableObject {
    @Published private(set) var status: String = "Starting…"

    private var transport: HTTPSSETransport?

    func start() {
        guard transport == nil else { return }

        #if canImport(AppIntents)
        if #available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *) {
            let server = IntentsDemoServer()
            let transport = HTTPSSETransport(server: server, port: 0)
            transport.serveOpenAPI = true
            self.transport = transport

            Task {
                do {
                    try await transport.start()
                    status = "Serving at http://\(transport.host):\(transport.port)/sse"
                } catch {
                    status = "Server failed: \(error.localizedDescription)"
                }
            }
        } else {
            status = "Requires AppIntents (iOS 16 / macOS 13 / tvOS 16 / watchOS 9)"
        }
        #else
        status = "AppIntents framework unavailable"
        #endif
    }

    func stop() {
        guard let transport else { return }
        Task {
            try? await transport.stop()
            self.transport = nil
            status = "Stopped"
        }
    }
}
