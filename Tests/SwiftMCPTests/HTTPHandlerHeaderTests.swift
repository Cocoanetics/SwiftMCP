#if Server
import Testing
import HTTPTypes
@testable import SwiftMCP

@Suite("HTTP Handler Header Tests")
struct HTTPHandlerHeaderTests {
    private func count(of name: HTTPField.Name, in fields: HTTPFields) -> Int {
        fields.filter { $0.name == name }.count
    }

    @Test("Route-provided CORS and Content-Length headers are not duplicated")
    func routeHeadersAreNotDuplicated() {
        let fields = HTTPResponseDefaults.buffered(
            [
                .accessControlAllowOrigin: "https://example.com",
                .contentType: "text/plain; charset=utf-8",
                .contentLength: "5"
            ],
            bodyLength: 5
        )

        #expect(fields[.accessControlAllowOrigin] == "https://example.com")
        #expect(fields[.contentLength] == "5")
        #expect(fields[.contentType] == "text/plain; charset=utf-8")
        // Defaults replace rather than append, so each field appears exactly once.
        #expect(count(of: .accessControlAllowOrigin, in: fields) == 1)
        #expect(count(of: .contentLength, in: fields) == 1)
        #expect(count(of: .contentType, in: fields) == 1)
    }

    @Test("Framework defaults are applied once when headers are missing")
    func frameworkDefaultsAreAppliedWhenMissing() {
        let fields = HTTPResponseDefaults.buffered([:], bodyLength: 5)

        #expect(fields[.accessControlAllowOrigin] == "*")
        #expect(fields[.contentLength] == "5")
        #expect(fields[.contentType] == "text/plain; charset=utf-8")
    }

    @Test("Existing Content-Length is preserved for empty-body responses")
    func existingContentLengthIsPreservedWithoutBody() {
        let fields = HTTPResponseDefaults.buffered(
            [.contentLength: "0"],
            bodyLength: nil
        )

        #expect(fields[.accessControlAllowOrigin] == "*")
        #expect(fields[.contentLength] == "0")
        #expect(fields[.contentType] == nil)
    }
}
#endif
