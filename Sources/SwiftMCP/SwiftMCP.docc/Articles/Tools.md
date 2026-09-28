# Tools

Learn how to expose functions as MCP tools using the ``MCPTool`` macro.

## Overview

Tools are the primary way to call functionality on a SwiftMCP server. By decorating a
function with ``MCPTool`` the macro generates the metadata needed for JSON-RPC and
OpenAPI integration. Documentation comments become the tool description and parameter
information automatically.

```swift
@MCPServer
actor ExampleServer {
    /// Adds two numbers
    /// - Parameters:
    ///   - a: First number
    ///   - b: Second number
    /// - Returns: The sum
    @MCPTool
    func add(a: Int, b: Int) -> Int {
        a + b
    }
}
```

Each ``MCPTool`` can be marked as consequential or not using the `isConsequential`
parameter. This value is exported in the OpenAPI schema and allows clients to decide if
calling the tool has side effects.

### Errors

A tool that throws is answered with `isError: true` and the error's localized description
as its text, which every MCP client reads. To give a client more than the text, such as an
error code or the data behind it, conform the error to ``MCPToolErrorMetaProviding``. Its
``MCPToolErrorMetaProviding/toolErrorMeta`` goes out as the result's `_meta`, beside the text.

```swift
struct QuotaExceeded: MCPToolErrorMetaProviding, LocalizedError {
    let limit: Int
    var errorDescription: String? { "Quota of \(limit) requests exceeded" }
    var toolErrorMeta: JSONDictionary { ["com.example/quota": ["limit": .integer(limit)]] }
}
```

A SwiftMCP client throws such a result as ``MCPServerProxyError/toolErrorWithMeta(_:meta:)``,
with the message and the `_meta`. A failed call without `_meta` is
``MCPServerProxyError/toolError(_:)``, as before.

### Completions

Parameter completion values can be provided by conforming your server to
``MCPCompletionProviding``. If no custom completions are supplied, SwiftMCP provides
default suggestions for ``Bool`` parameters and any ``CaseIterable`` enum.
