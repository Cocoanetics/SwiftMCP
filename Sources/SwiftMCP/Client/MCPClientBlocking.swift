import Dispatch
import Foundation

/// Bridges async MCP proxy calls for synchronous client methods.
public enum MCPClientBlocking {
    public static func call<T>(_ operation: @escaping @Sendable () async throws -> T) throws -> T {
        let semaphore = DispatchSemaphore(value: 0)
        let box = ResultBox<T>()

        Task {
            do {
                let value = try await operation()
                box.set(.success(value))
            } catch {
                box.set(.failure(error))
            }
            semaphore.signal()
        }

        semaphore.wait()

        guard let result = box.get() else {
            throw MCPServerProxyError.communicationError("Blocking client call failed to produce a result.")
        }
        return try result.get()
    }
}

private final class ResultBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Result<T, Error>?

    func set(_ result: Result<T, Error>) {
        lock.lock()
        value = result
        lock.unlock()
    }

    func get() -> Result<T, Error>? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
