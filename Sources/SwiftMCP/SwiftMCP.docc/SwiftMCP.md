# ``SwiftMCP``

A framework for exposing Swift functions as tools that can be called by AI assistants.

## Overview

SwiftMCP provides a powerful way to expose Swift functions as tools that can be called by AI assistants. The framework offers:

- Documentation-driven tool definitions
- Multiple transport options (HTTP+SSE, stdio)
- OpenAPI specification generation
- AI plugin manifest generation

### Documentation-Driven Development

Define your tools using Swift's native documentation comments. SwiftMCP automatically extracts descriptions, parameter info, and return types.

### Multiple Transport Options

Choose between HTTP+SSE for web integration or stdio for command-line tools. Easy to extend with custom transports.

### OpenAPI Compatible

Automatically generate OpenAPI specifications from your tool definitions for easy integration with existing tools.

### AI-Ready Integration

Generate AI plugin manifests and function schemas compatible with leading AI platforms.

## Getting Started

To start using SwiftMCP, first create a server that exposes your tools:

```swift
@MCPServer
class Calculator {
    @MCPTool
    func add(a: Int, b: Int) -> Int {
        a + b
    }
}
```

Then choose a transport to expose your server:

```swift
let calculator = Calculator()
let transport = HTTPSSETransport(server: calculator)
try await transport.run()
```

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