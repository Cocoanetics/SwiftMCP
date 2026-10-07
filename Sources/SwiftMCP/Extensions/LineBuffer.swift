import Foundation

/// Newline framing shared by ``LineBuffer`` and ``LineFramer``.
///
/// A JSON-RPC message is a single line and can be large: a raw email returned as base64 runs
/// to 100 MB. Each search for the next newline continues where the previous one stopped, so
/// assembling a line takes time linear in its length. Searching the whole buffer again for
/// every received chunk was quadratic, and a 100 MB line arriving in 64 KB chunks took minutes.
struct LineAssembler {
    private var buffer = Data()
    /// Number of bytes at the start of `buffer` already searched for a newline.
    private var searched = 0

    mutating func append(_ data: Data) {
        buffer.append(data)
    }

    /// Removes and returns every complete newline-terminated line.
    mutating func extractLines() -> [String] {
        let searchStart = searched
        let newlineOffsets: [Int] = buffer.withUnsafeBytes { bytes in
            var offsets: [Int] = []
            var offset = searchStart
            while offset < bytes.count {
                if bytes[offset] == 0x0A {
                    offsets.append(offset)
                }
                offset += 1
            }
            return offsets
        }
        searched = buffer.count

        guard let lastNewline = newlineOffsets.last else {
            return []
        }

        var lines: [String] = []
        lines.reserveCapacity(newlineOffsets.count)
        var lineStart = buffer.startIndex
        for newline in newlineOffsets {
            let lineEnd = buffer.startIndex + newline
            if let line = String(data: buffer[lineStart..<lineEnd], encoding: .utf8) {
                lines.append(line)
            }
            lineStart = lineEnd + 1
        }

        // Everything after the last newline has been searched already.
        buffer.removeSubrange(buffer.startIndex...(buffer.startIndex + lastNewline))
        searched = buffer.count
        return lines
    }

    /// Removes and returns the final unterminated line, if any.
    mutating func remainder() -> String? {
        guard !buffer.isEmpty else { return nil }
        let remaining = buffer
        buffer.removeAll()
        searched = 0
        return String(data: remaining, encoding: .utf8)
    }
}

/// Buffers bytes to return full newline-delimited lines.
///
/// Shared by both the client connections (`Client`) and the TCP server
/// transport (`Server`), so it lives in the always-on core rather than behind
/// a feature trait.
actor LineBuffer {
    private var assembler = LineAssembler()

    func append(_ data: Data) {
        assembler.append(data)
    }

    func processLines() -> [String] {
        assembler.extractLines()
    }

    func getRemaining() -> String? {
        assembler.remainder()
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
    private var assembler = LineAssembler()

    func append(_ data: Data) {
        assembler.append(data)
    }

    /// Removes and returns every complete newline-terminated line.
    func extractLines() -> [String] {
        assembler.extractLines()
    }

    /// Removes and returns the final unterminated line, if any.
    func remainder() -> String? {
        assembler.remainder()
    }
}
