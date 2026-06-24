//
//  Exports.swift
//  SwiftMCP
//
//  Re-exports the standalone `JSONFoundation` module so that existing code can
//  keep using `JSONValue`, `JSONSchema`, the JSON-RPC types and friends via
//  `import SwiftMCP`.
//
//  `JSONFoundation` is intentionally dependency-free (Foundation only) so it can
//  be consumed on its own — e.g. from SwiftAgents — without pulling in
//  SwiftNIO, swift-crypto or the rest of the SwiftMCP dependency graph.
//

@_exported import JSONFoundation
