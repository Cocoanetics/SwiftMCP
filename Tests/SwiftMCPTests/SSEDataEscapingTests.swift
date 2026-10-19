#if Server
import Testing
import Foundation
@testable import SwiftMCP

@Suite("SSE Data Escaping")
struct SSEDataEscapingTests {
    @Test("Escapes NEL, LINE SEPARATOR and PARAGRAPH SEPARATOR as \\uXXXX")
    func escapesUnicodeLineBreaks() throws {
        let value = "a\u{85}b\u{2028}c\u{2029}d"
        let json = try #require(String(data: try JSONEncoder().encode(value), encoding: .utf8))

        let escaped = json.escapingUnicodeLineBreaksForSSE

        #expect(escaped == "\"a\\u0085b\\u2028c\\u2029d\"")
        let decoded = try JSONDecoder().decode(String.self, from: Data(escaped.utf8))
        #expect(decoded == value)
    }

    @Test("Leaves text without Unicode line breaks unchanged")
    func leavesPlainTextUnchanged() {
        let json = "{\"jsonrpc\":\"2.0\",\"result\":\"ä\\n\u{1F600}\"}"
        #expect(json.escapingUnicodeLineBreaksForSSE == json)
    }
}
#endif
