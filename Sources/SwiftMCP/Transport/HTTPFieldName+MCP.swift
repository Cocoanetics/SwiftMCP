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

	/// `Last-Event-ID` — the SSE resumption cursor used to resume a broken
	/// streamable-HTTP / legacy-SSE stream.
	public static let lastEventID = Self("Last-Event-ID")!
}
