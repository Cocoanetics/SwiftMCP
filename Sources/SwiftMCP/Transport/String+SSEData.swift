#if Server
import Foundation

extension String {
    /// JSON text made safe for an SSE `data:` line.
    ///
    /// `JSONEncoder` leaves NEL (U+0085), LINE SEPARATOR (U+2028) and PARAGRAPH SEPARATOR (U+2029)
    /// unescaped, but many line readers (Foundation's `AsyncBytes.lines` among them) break lines
    /// there, cutting one message in two. In JSON these characters can only occur inside string
    /// literals, so writing them as `\uXXXX` escapes keeps the text equivalent.
    var escapingUnicodeLineBreaksForSSE: String {
        guard unicodeScalars.contains(where: { $0.isUnicodeLineBreak }) else {
            return self
        }

        var result = String.UnicodeScalarView()
        for scalar in unicodeScalars {
            if scalar.isUnicodeLineBreak {
                result.append(contentsOf: String(format: "\\u%04X", scalar.value).unicodeScalars)
            } else {
                result.append(scalar)
            }
        }
        return String(result)
    }
}

private extension Unicode.Scalar {
    var isUnicodeLineBreak: Bool {
        switch value {
        case 0x85, 0x2028, 0x2029:
            return true
        default:
            return false
        }
    }
}
#endif
