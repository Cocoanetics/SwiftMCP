//
//  JSONRPCFrame.swift
//  SwiftMCP
//
//  Wire encoding for a JSON-RPC frame shared by the bundled transports.
//

import Foundation

/// Wire-format helpers for a JSON-RPC *frame* (an array of ``JSONRPCMessage``).
///
/// Connection-based transports that speak a byte stream (stdio, TCP) use this to
/// turn an outbound frame into a single JSON payload, matching the historical
/// encoding: a one-element frame is written as a single message object, a
/// multi-element frame as a JSON array (a batch). Keys are sorted and dates use
/// ISO-8601 with a time zone, identical to the legacy `Transport.send` path.
enum JSONRPCFrame {
    /// Encodes a frame to a single JSON payload.
    ///
    /// - Parameter frame: One or more JSON-RPC messages.
    /// - Returns: JSON data — a bare object for a single message, an array for a
    ///   batch.
    static func encode(_ frame: [JSONRPCMessage]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601WithTimeZone
        encoder.outputFormatting = [.sortedKeys]
        if frame.count == 1 {
            return try encoder.encode(frame[0])
        }
        return try encoder.encode(frame)
    }
}
