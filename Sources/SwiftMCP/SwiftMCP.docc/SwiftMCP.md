# ``SwiftMCP``

A framework for building AI-powered tools and plugins.

## Overview

SwiftMCP (Machine Control Protocol) is a framework that helps you expose Swift functions as tools that can be called by AI assistants. It provides:

- Documentation-driven tool definitions
- Multiple transport options (HTTP+SSE, stdio)
- OpenAPI specification generation
- AI plugin manifest generation

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