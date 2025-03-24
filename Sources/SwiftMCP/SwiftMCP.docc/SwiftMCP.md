# ``SwiftMCP``

A Swift framework that makes it easy to expose your functions as Model Context Protocol (MCP) tools for AI assistants.

## Overview

SwiftMCP lets you turn any Swift function into an MCP tool with just a single decorator. It handles all the complexity of JSON-RPC communication, parameter validation, and documentation generation, letting you focus on writing your tool's logic.

```swift
@MCPServer
class Calculator {
    @MCPTool
    func add(a: Int, b: Int) -> Int {
        a + b
    }
}
```

The framework automatically:
- Extracts documentation from your Swift comments to describe tools
- Validates and converts parameters to the correct types
- Generates OpenAPI specifications for AI integration
- Provides multiple transport options (HTTP+SSE, stdio)

### Key Features

- **Documentation-Driven**: Your standard Swift documentation comments are automatically turned into tool descriptions, parameter info, and return type documentation.
- **Type-Safe**: All parameters are automatically validated and converted to their correct Swift types.
- **AI-Ready**: Built-in support for OpenAPI specification generation and AI plugin manifests.
- **Flexible Transport**: Choose between HTTP+SSE for web applications or stdio for command-line tools.

## Next Steps

Start with <doc:GettingStarted> to create your first MCP server, then explore <doc:CoreConcepts> to understand how SwiftMCP uses documentation to power AI interactions.

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:CoreConcepts>
- <doc:SwiftMCPTutorials>

### Macros

- ``MCPServer``
- ``MCPTool``

### Core Types

- ``MCPToolMetadata``
- ``MCPToolParameterInfo``
- ``MCPToolError``

### Server Components

- ``Transport``
- ``HTTPSSETransport``
- ``StdioTransport``

```swift
@MCPServer(version: "1.0.0")
struct Calculator {
    @MCPTool(description: "Adds two numbers")
    func add(a: Double, b: Double) -> Double {
        return a + b
    }
}
``` 