import Foundation

/// Buffers bytes to return full newline-delimited lines.
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
