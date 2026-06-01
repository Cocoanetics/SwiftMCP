//
//  Exports.swift
//  SwiftMCP
//
//  Re-exports the standalone `JSONValue` module so that existing code can
//  keep using `JSONValue`, `JSONSchema` and friends via `import SwiftMCP`.
//
//  `JSONValue` is intentionally dependency-free (Foundation only) so it can
//  be consumed on its own — e.g. from SwiftAgents — without pulling in
//  SwiftNIO, swift-crypto or the rest of the SwiftMCP dependency graph.
//

@_exported import JSONValue
