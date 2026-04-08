import Testing
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import SwiftMCP

@Suite("HTTP Handler Header Tests")
struct HTTPHandlerHeaderTests {
    private func values(named name: String, in headers: [(String, String)]) -> [String] {
        headers
            .filter { $0.0.caseInsensitiveCompare(name) == .orderedSame }
            .map(\.1)
    }

    @Test("Route-provided CORS and Content-Length headers are not duplicated")
    func routeHeadersAreNotDuplicated() {
        let headers = HTTPHandler.responseHeadersApplyingDefaults(
            [
                ("Access-Control-Allow-Origin", "https://example.com"),
                ("Content-Type", "text/plain; charset=utf-8"),
                ("Content-Length", "5")
            ],
            bodyLength: 5
        )

        #expect(values(named: "Access-Control-Allow-Origin", in: headers) == ["https://example.com"])
        #expect(values(named: "Content-Length", in: headers) == ["5"])
        #expect(values(named: "Content-Type", in: headers) == ["text/plain; charset=utf-8"])
    }

    @Test("Framework defaults are applied once when headers are missing")
    func frameworkDefaultsAreAppliedWhenMissing() {
        let headers = HTTPHandler.responseHeadersApplyingDefaults([], bodyLength: 5)

        #expect(values(named: "Access-Control-Allow-Origin", in: headers) == ["*"])
        #expect(values(named: "Content-Length", in: headers) == ["5"])
        #expect(values(named: "Content-Type", in: headers) == ["text/plain; charset=utf-8"])
    }

    @Test("Existing Content-Length is preserved for empty-body responses")
    func existingContentLengthIsPreservedWithoutBody() {
        let headers = HTTPHandler.responseHeadersApplyingDefaults(
            [("Content-Length", "0")],
            bodyLength: nil
        )

        #expect(values(named: "Access-Control-Allow-Origin", in: headers) == ["*"])
        #expect(values(named: "Content-Length", in: headers) == ["0"])
        #expect(values(named: "Content-Type", in: headers).isEmpty)
    }
}
