//
//  DocCommentParser.swift
//  SwiftMCPAggregatorTool
//
//  Parses Swift doc comments off of leading trivia into description,
//  per-parameter blurbs, and a single returns line.
//

import Foundation
import SwiftSyntax

func parseDocComment(trivia: Trivia) -> ParsedDocComment {
    let lines = extractDocLines(from: trivia)

    var description: [String] = []
    var params: [String: String] = [:]
    var returns: String?
    for line in lines {
        classifyDocLine(line, description: &description, params: &params, returns: &returns)
    }

    let descText = description.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    return ParsedDocComment(
        description: descText.isEmpty ? nil : descText,
        params: params,
        returns: returns
    )
}

/// Flatten the trivia into one trimmed string per doc-comment line.
private func extractDocLines(from trivia: Trivia) -> [String] {
    var lines: [String] = []
    for piece in trivia.pieces {
        switch piece {
        case .docLineComment(let raw):
            lines.append(stripDocLineComment(raw))
        case .docBlockComment(let raw):
            lines.append(contentsOf: stripDocBlockComment(raw))
        default:
            break
        }
    }
    return lines
}

private func stripDocLineComment(_ raw: String) -> String {
    var line = raw
    if line.hasPrefix("///") { line.removeFirst(3) }
    return line.trimmingCharacters(in: .whitespaces)
}

private func stripDocBlockComment(_ raw: String) -> [String] {
    var stripped = raw
    if stripped.hasPrefix("/**") { stripped.removeFirst(3) }
    if stripped.hasSuffix("*/") { stripped.removeLast(2) }
    var out: [String] = []
    for sub in stripped.split(separator: "\n", omittingEmptySubsequences: false) {
        var line = sub.trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("*") { line.removeFirst() }
        out.append(line.trimmingCharacters(in: .whitespaces))
    }
    return out
}

/// Routes a single doc-comment line into the right bucket. Pulled out so
/// `parseDocComment` stays within the cyclomatic-complexity budget.
private func classifyDocLine(
    _ line: String,
    description: inout [String],
    params: inout [String: String],
    returns: inout String?
) {
    if line.hasPrefix("- Parameter ") {
        let body = String(line.dropFirst("- Parameter ".count))
        if let colonIdx = body.firstIndex(of: ":") {
            let name = body[..<colonIdx].trimmingCharacters(in: .whitespaces)
            let desc = body[body.index(after: colonIdx)...].trimmingCharacters(in: .whitespaces)
            params[name] = desc
        }
    } else if line.hasPrefix("- Returns:") {
        returns = String(line.dropFirst("- Returns:".count)).trimmingCharacters(in: .whitespaces)
    } else if line.hasPrefix("- Throws:") {
        // ignored
    } else {
        description.append(line)
    }
}
