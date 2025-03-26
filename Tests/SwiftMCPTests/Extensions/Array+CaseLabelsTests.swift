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
        // Test that we get the correct labels for a CaseIterable enum
        let labels = Array<String>(caseLabelsFrom: Options.self)
        #expect(labels != nil)
        #expect(labels == ["all", "unread", "starred"])
    }
    
    @Test("Case labels from non-enum")
    func testCaseLabelsFromNonEnum() throws {
        // Test that we get nil for a non-CaseIterable type
        let labels = Array<String>(caseLabelsFrom: Int.self)
        #expect(labels == nil)
    }
}
