import Foundation

protocol StdioConnection: Sendable {
    func lines() async -> AsyncThrowingStream<String, Error>
    func start() async throws
    func write(_ data: Data) async
    func stop() async
}
