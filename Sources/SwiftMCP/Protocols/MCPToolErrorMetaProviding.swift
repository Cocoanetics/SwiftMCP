//
//  MCPToolErrorMetaProviding.swift
//  SwiftMCP
//

/**
 An error a tool throws with details for the client, beyond its message.

 A tool that fails is answered with `isError: true` and the error's text, which every MCP
 client reads. An error conforming to this protocol adds its ``toolErrorMeta`` to that result
 as `_meta`, so a client that knows the keys can act on the details: an error code, the data
 behind it, whether a retry could help. A SwiftMCP client throws such a result as
 ``MCPServerProxyError/toolErrorWithMeta(_:meta:)``.

 ```swift
 struct ModeRefused: MCPToolErrorMetaProviding, LocalizedError {
     let code: Int
     var errorDescription: String? { "The agent refused the mode" }
     var toolErrorMeta: JSONDictionary { ["com.example/error": ["code": .integer(code)]] }
 }
 ```

 Name the keys with a prefix of your own (`com.example/…`): MCP reserves `_meta` keys whose
 prefix names `modelcontextprotocol` or `mcp`.
 */
public protocol MCPToolErrorMetaProviding: Error {
    /// The `_meta` for the tool's error result. An empty dictionary sends none.
    var toolErrorMeta: JSONDictionary { get }
}
