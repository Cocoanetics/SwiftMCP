import Foundation
import Testing
import SwiftMCP

/// A server whose tool doc comments contain content that previously broke
/// macro expansion: embedded `"…"` strings and a `**/*` glob example (whose
/// inner `*/` substring closed the generated `/** … */` block comment early).
///
/// Regression test for https://github.com/Cocoanetics/SwiftMCP/issues/121
@MCPServer
final class Issue121Server {
    /// Search files.
    /// - Parameter pattern: The regex pattern.
    /// - Parameter outputMode: "content" shows matching lines, "files" shows only file paths.
    /// - Parameter glob: e.g. "*.swift" or "*.ts". Do NOT use "**/*".
    @MCPTool
    func grep(pattern: String, outputMode: String, glob: String? = nil) -> String {
        ""
    }
}

@Suite("Issue 121 Reproducer", .tags(.client))
struct Issue121ReproTests {
    @Test("Macro expands cleanly with quoted/asterisk doc-comment content")
    func macroExpandsWithQuotedAsteriskDocs() {
        let server = Issue121Server()
        let metadata = server.mcpToolMetadata
        #expect(metadata.count == 1)

        let tool = try? #require(metadata.first)
        #expect(tool?.name == "grep")
        // Parameter descriptions survive the round trip unchanged.
        let parameters = Dictionary(uniqueKeysWithValues: (tool?.parameters ?? []).map { ($0.name, $0) })
        #expect(parameters["outputMode"]?.description?.contains("\"content\"") == true)
        #expect(parameters["glob"]?.description?.contains("\"**/*\"") == true)
    }
}
