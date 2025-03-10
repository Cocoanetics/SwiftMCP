# SwiftMCP

SwiftMCP is a Swift library that makes supporting the Model Context Protocol (MCP) easy. It uses Swift macros to automatically extract function metadata and generate the necessary JSON-RPC interface for MCP communication.

## What is MCP?

The Model Context Protocol (MCP) is a standardized way for AI models to interact with external tools and services. SwiftMCP makes it simple to expose your Swift functions as MCP-compatible tools that can be called by AI models.

## MCP Transport Modes

MCP supports two transport modes:

- **stdio mode** ✅ - Fully implemented in SwiftMCP
  - Communication happens over standard input/output
  - Simple to implement and use for command-line tools
  - Perfect for local development and testing

- **HTTP+SSE mode** ⏳ - Not yet implemented
  - Communication over HTTP with Server-Sent Events
  - Better for networked applications and services
  - Coming in a future release

## Features

- **Simple Macro-Based API**: Just add `@MCPServer` and `@MCPTool` annotations to your code
- **Automatic Documentation Extraction**: Parameter names, types, and descriptions are extracted from your Swift documentation
- **JSON-RPC Interface**: Fully compliant with the MCP specification
- **Type Safety**: Leverages Swift's type system for safe parameter handling
- **Default Values Support**: Handles parameters with default values
- **Command-Line Interface**: Ready-to-use CLI for testing and integration

## Quick Start

Here's how to create an MCP-compatible server in just a few lines of code:

```swift
import SwiftMCP

// 1. Annotate your class with @MCPServer
@MCPServer(name: "MyCalculator", version: "1.0.0")
class Calculator {
    // 2. Add documentation comments that describe your function and parameters
    /// Adds two integers and returns their sum
    /// - Parameter a: First number to add
    /// - Parameter b: Second number to add
    /// - Returns: The sum of a and b
    // 3. Annotate your function with @MCPTool
    @MCPTool
    func add(a: Int, b: Int) -> Int {
        return a + b
    }
    
    /// Divides the numerator by the denominator
    /// - Parameter numerator: Number to be divided
    /// - Parameter denominator: Number to divide by (defaults to 1.0)
    /// - Returns: The quotient of numerator divided by denominator
    @MCPTool
    func divide(numerator: Double, denominator: Double = 1.0) -> Double {
        return numerator / denominator
    }
}

// 4. That's it! Your class now has MCP capabilities
let calculator = Calculator()

// Process MCP requests
let request = JSONRPCRequest(
    jsonrpc: "2.0",
    id: 1,
    method: "tools/call",
    params: [
        "name": AnyCodable("add"),
        "arguments": AnyCodable(["a": 5, "b": 3])
    ]
)

// The response will be a properly formatted MCP response
let response = calculator.handleRequest(request)
```

## How It Works

SwiftMCP uses Swift macros to analyze your code at compile time:

1. **Documentation Extraction**: The `@MCPTool` macro extracts parameter names, types, and descriptions from your documentation comments
2. **Schema Generation**: It automatically generates JSON Schema for your function parameters
3. **Server Configuration**: The `@MCPServer` macro adds the necessary infrastructure to handle JSON-RPC requests

## JSON-RPC Interface

SwiftMCP implements the standard MCP JSON-RPC interface:

- `initialize`: Sets up the connection and returns server capabilities
- `tools/list`: Returns a list of available tools with their schemas
- `tools/call`: Calls a specific tool with the provided arguments

## Command-Line Interface

SwiftMCP includes a ready-to-use command-line interface for stdio mode:

```bash
# Process a single request
echo '{"jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": {"name": "divide", "arguments": {"numerator": 10}}}' | swift run SwiftMCPDemo
```

## Advanced Usage

### Custom Tool Descriptions

You can provide a custom description for a tool:

```swift
@MCPTool(description: "Custom description for this tool")
func myFunction(param: String) -> String {
    // ...
}
```

### Server Name and Version

Customize your server's name and version:

```swift
@MCPServer(name: "MyCustomServer", version: "2.5.0")
class MyServer {
    // ...
}
```

## Requirements

- Swift 5.9 or later
- macOS 13.0 or later

## Installation

Add SwiftMCP to your Swift package dependencies:

```swift
dependencies: [
    .package(url: "https://github.com/yourusername/SwiftMCP.git", from: "1.0.0")
]
```

## License

This project is licensed under the MIT License - see the LICENSE file for details. 
