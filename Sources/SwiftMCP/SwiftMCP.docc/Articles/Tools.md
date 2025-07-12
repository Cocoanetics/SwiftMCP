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

### Completions

Parameter completion values can be provided by conforming your server to
``MCPCompletionProviding``. If no custom completions are supplied, SwiftMCP provides
default suggestions for ``Bool`` parameters and any ``CaseIterable`` enum.
