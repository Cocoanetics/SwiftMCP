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
//  The JSON-RPC *runtime* modules are re-exported too, so the shared
//  `JSONRPCPeer` / `JSONRPCMessageTransport` / framing types — the seam SwiftMCP
//  now unifies on with LSP and SwiftACP — are visible through `import SwiftMCP`.
//

@_exported import JSONFoundation
@_exported import JSONRPCPeer
@_exported import JSONRPCWire
// The transport-agnostic SSE *server* registry (replay/resume/retention) plus its
// SSE value types (`SSEMessage` / `SSEEventID`) — the HTTP/SSE `SessionManager`
// delegates its stream registry to it. Server-only.
#if Server
@_exported import JSONRPCSSEServer
#endif
// The POSIX-socket TCP client transport — client-only (it backs the client's
// direct host:port connections).
#if Client
@_exported import JSONRPCTCP
#endif
// The swift-subprocess stdio transport is trait- and platform-gated (see
// Package.swift); re-export it only where it is actually linked.
#if Client && (os(macOS) || os(Linux) || os(Windows))
@_exported import JSONRPCSubprocess
#endif
