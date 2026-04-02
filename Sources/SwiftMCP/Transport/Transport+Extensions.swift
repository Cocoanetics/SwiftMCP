import Foundation
import Logging

// MARK: - Default Implementations

public extension Transport {
    /// Encode and send an `Encodable` value as JSON.
    ///
    /// Transports only need to implement `send(_:)` for sending raw `Data`.
    func send<T: Encodable>(_ json: T) async throws {
        let dataToEncode: any Encodable

        if let array = json as? [any Encodable], array.count == 1 {
            // send a single JSON dictionary instead of an array with one element
            dataToEncode = array[0]
        } else {
            dataToEncode = json
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601WithTimeZone
        encoder.outputFormatting = [.sortedKeys]

        let data = try encoder.encode(dataToEncode)

        try await send(data)
    }
}
