import Foundation
import NIOCore

extension JSONRPCMessage {
    /// Decode a single or batched JSON-RPC payload from `Data`.
    /// - Parameter data: Raw JSON data.
    /// - Returns: An array of `JSONRPCMessage` items.
    static func decodeMessages(from data: Data) throws -> [JSONRPCMessage] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let batch = try? decoder.decode([JSONRPCMessage].self, from: data) {
            return batch
        } else {
            let single = try decoder.decode(JSONRPCMessage.self, from: data)
            return [single]
        }
    }

    /// Decode a single or batched JSON-RPC payload from a `ByteBuffer`.
    /// - Parameter buffer: Incoming buffer containing JSON data.
    static func decodeMessages(from buffer: ByteBuffer) throws -> [JSONRPCMessage] {
        var copy = buffer
        guard let data = copy.readData(length: copy.readableBytes) else {
            return []
        }
        return try decodeMessages(from: data)
    }
}
