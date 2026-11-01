//
//  HTTPFieldName+MCP.swift
//  SwiftMCP
//
//  Typed `HTTPField.Name` constants for the MCP-specific HTTP headers. Defined
//  in the core (not behind the `Server` trait) so the client transport and the
//  server routing layer share a single, validated source of truth for these
//  field names instead of repeating string literals that a typo would silently
//  break.
//

import HTTPTypes

extension HTTPField.Name {
	/// `Mcp-Session-Id` — the MCP session identifier exchanged on every
	/// streamable-HTTP request/response.
	public static let mcpSessionID = Self("Mcp-Session-Id")!

	/// `MCP-Protocol-Version` — the negotiated MCP protocol version.
	public static let mcpProtocolVersion = Self("MCP-Protocol-Version")!

	/// `Mcp-Method` — mirrors the JSON-RPC `method` on a modern (`2026-07-28`)
	/// request, validated against the body.
	public static let mcpMethod = Self("Mcp-Method")!

	/// `Mcp-Name` — mirrors `params.name` (`tools/call` / `prompts/get`) or
	/// `params.uri` (`resources/read`) on a modern request, validated against the
	/// body.
	public static let mcpName = Self("Mcp-Name")!

	/// `Last-Event-ID` — the SSE resumption cursor used to resume a broken
	/// streamable-HTTP / legacy-SSE stream.
	public static let lastEventID = Self("Last-Event-ID")!

	/// `X-Accel-Buffering` — set to `no` on modern per-request SSE responses so
	/// buffering reverse proxies (nginx et al.) pass events through immediately.
	public static let xAccelBuffering = Self("X-Accel-Buffering")!
}

extension HTTPField.Name {
	/// The request headers a cross-origin MCP client may send: the legacy set plus
	/// the modern routing headers (`Mcp-Method`, `Mcp-Name`) and `Last-Event-ID`.
	/// `Mcp-Param-*` is a dynamic family, so it is covered by the `*` wildcard —
	/// which does not match `Authorization`, so that is still named explicitly.
	public static let corsAllowedRequestHeaders =
		"Content-Type, Content-Disposition, Authorization, Accept, MCP-Protocol-Version, "
		+ "Mcp-Session-Id, Mcp-Method, Mcp-Name, Last-Event-ID, *"

	/// The response headers a browser client must be able to read.
	public static let corsExposedResponseHeaders = "Mcp-Session-Id, MCP-Protocol-Version"
}
