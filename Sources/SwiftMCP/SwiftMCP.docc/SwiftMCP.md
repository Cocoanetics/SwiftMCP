# ``SwiftMCP``

A Swift framework for building Model Control Protocol (MCP) servers.

## Overview

SwiftMCP provides a simple and type-safe way to build MCP servers in Swift. Using Swift's macro system, it automatically handles JSON-RPC communication, parameter validation, and OpenAPI specification generation.

```swift
@MCPServer(version: "1.0.0")
struct Calculator {
    @MCPTool(description: "Adds two numbers")
    func add(a: Double, b: Double) -> Double {
        return a + b
    }
}
```

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:SwiftMCPTutorials>

### Macros

- ``MCPServer``
- ``MCPTool``

### Core Types

- ``MCPToolMetadata``
- ``MCPToolParameterInfo``
- ``MCPToolError``

### Server Components

- ``StdioTransport``
- ``HTTPSSETransport`` 