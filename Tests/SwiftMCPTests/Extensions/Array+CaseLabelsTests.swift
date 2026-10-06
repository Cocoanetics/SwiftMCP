import Testing
@testable import SwiftMCP

enum Options: CaseIterable {
    case all
    case unread
    case starred
}

@Suite("Array+CaseLabels")
struct ArrayCaseLabelsTests {
    @Test("Case labels from enum")
    func testCaseLabelsFromEnum() throws {
        // The labels of a CaseIterable enum, through the API that replaced
        // the deprecated initializer.
        #expect(Options.caseLabels == ["all", "unread", "starred"])
    }

    // The deprecated initializer still has to answer nil for a type that is
    // not CaseIterable; a deprecated test may call it without a warning.
    @available(*, deprecated, message: "Tests the deprecated initializer")
    @Test("Case labels from non-enum")
    func testCaseLabelsFromNonEnum() throws {
        let labels = [String](caseLabelsFrom: Int.self)
        #expect(labels == nil)
    }
}
