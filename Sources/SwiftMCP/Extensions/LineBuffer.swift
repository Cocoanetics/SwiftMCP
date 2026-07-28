import Foundation

/// Buffers bytes to return full newline-delimited lines.
///
/// Shared by both the client connections (`Client`) and the TCP server
/// transport (`Server`), so it lives in the always-on core rather than behind
/// a feature trait.
actor LineBuffer {
    private var buffer = Data()

    func append(_ data: Data) {
        buffer.append(data)
    }

    func processLines() -> [String] {
        var lines: [String] = []
        while let range = buffer.firstRange(of: Data([0x0A])) {
            let lineData = buffer[..<range.lowerBound]
            buffer.removeSubrange(..<range.upperBound)

            if let line = String(data: lineData, encoding: .utf8) {
                lines.append(line)
            }
        }
        return lines
    }

    func getRemaining() -> String? {
        guard !buffer.isEmpty else { return nil }
        let remaining = buffer
        buffer.removeAll()
        return String(data: remaining, encoding: .utf8)
    }
}

/// Synchronous sibling of ``LineBuffer`` for callers that are already serialized.
///
/// The TCP server transport assembles lines *inside* `NWConnection` receive
/// callbacks, which all run on the connection's serial dispatch queue. Hopping
/// each chunk into the `LineBuffer` actor would discard that ordering: two
/// chunks race into the actor and can interleave mid-line, and the final
/// unterminated line on EOF races the chunk that carried it. Assembling
/// synchronously on the queue keeps the byte stream ordered by construction.
///
/// `@unchecked Sendable` is sound only under that confinement: every call must
/// come from the one serial queue the connection was started on.
final class LineFramer: @unchecked Sendable {
    private var buffer = Data()

    func append(_ data: Data) {
        buffer.append(data)
    }

    /// Removes and returns every complete newline-terminated line.
    func extractLines() -> [String] {
        var lines: [String] = []
        while let range = buffer.firstRange(of: Data([0x0A])) {
            let lineData = buffer[..<range.lowerBound]
            buffer.removeSubrange(..<range.upperBound)

            if let line = String(data: lineData, encoding: .utf8) {
                lines.append(line)
            }
        }
        return lines
    }

    /// Removes and returns the final unterminated line, if any.
    func remainder() -> String? {
        guard !buffer.isEmpty else { return nil }
        let remaining = buffer
        buffer.removeAll()
        return String(data: remaining, encoding: .utf8)
    }
}
