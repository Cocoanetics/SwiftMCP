import Testing
@testable import SwiftMCP

@Suite("String+ContentType")
struct StringContentTypeTests {
    @Test("Exact match")
    func testExactMatch() throws {
        #expect("application/json".matchesAcceptHeader("application/json"))
    }

    @Test("Wildcard subtype")
    func testWildcardSubtype() throws {
        #expect("application/json".matchesAcceptHeader("application/*"))
    }

    @Test("Universal match")
    func testUniversalMatch() throws {
        #expect("application/json".matchesAcceptHeader("*/*"))
    }

    @Test("Non-match cases")
    func testNonMatch() throws {
        #expect(!"application/json".matchesAcceptHeader("text/html"))
        #expect(!"application/json".matchesAcceptHeader("text/*"))
    }
}
