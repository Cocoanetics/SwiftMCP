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

    /// Computes something interesting.
    /// - Parameter input: The input value.
    /// - Returns: The first paragraph of the return docs.
    ///
    ///   A second paragraph separated by a blank line. `Documentation.combineLines`
    ///   collapses this into a single `Returns:` string with an embedded `\n\n`,
    ///   which must not break the generated `///` doc comments.
    @MCPTool
    func compute(input: String) -> String {
        input
    }
}

@Suite("Issue 121 Reproducer", .tags(.client))
struct Issue121ReproTests {
    @Test("Macro expands cleanly with quoted/asterisk doc-comment content")
    func macroExpandsWithQuotedAsteriskDocs() {
        let server = Issue121Server()
        let metadata = server.mcpToolMetadata
        #expect(metadata.count == 2)

        let grep = metadata.first { $0.name == "grep" }
        // Parameter descriptions survive the round trip unchanged.
        let parameters = Dictionary(uniqueKeysWithValues: (grep?.parameters ?? []).map { ($0.name, $0) })
        #expect(parameters["outputMode"]?.description?.contains("\"content\"") == true)
        #expect(parameters["glob"]?.description?.contains("\"**/*\"") == true)
    }

    @Test("Macro handles multi-paragraph `- Returns:` docs without leaking into source")
    func macroHandlesMultiParagraphReturns() {
        let server = Issue121Server()
        // The mere fact that this server compiles proves the regression is
        // fixed — if `lineDocCommentLines` did not split embedded newlines,
        // the second paragraph of `compute`'s `- Returns:` block would have
        // been emitted as raw Swift between the `///` doc comment and the
        // function signature, failing macro expansion.
        #expect(server.mcpToolMetadata.contains { $0.name == "compute" })
    }
}
