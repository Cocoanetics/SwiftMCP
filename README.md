# SwiftMCP

SwiftMCP is a Swift package that provides a way to generate JSON descriptions of functions for use in a Multi-Call Protocol (MCP) system. It uses Swift macros to extract function metadata at compile time.

## Features

- Automatically extracts function parameter types and return types
- Generates JSON descriptions of functions with proper type information
- Supports parameters with default values
- Handles numeric default values correctly in JSON output
- Simple to use with Swift macros

## Usage

```swift
import SwiftMCP

@MCPTool
class Calculator {
    /// Adds two integers and returns their sum
    /// - Parameter a: First number to add
    /// - Parameter b: Second number to add
    /// - Returns: The sum of a and b
    @MCPFunction
    func add(a: Int, b: Int) -> Int {
        return a + b
    }
    
    /// Subtracts the second integer from the first and returns the difference
    /// - Parameter a: Number to subtract from
    /// - Parameter b: Number to subtract (defaults to 3)
    /// - Returns: The difference between a and b
    @MCPFunction
    func subtract(a: Int, b: Int = 3) -> Int {
        return a - b
    }
}

// Get JSON descriptions of all functions
let tools = calculator.mcpTools
let json = MCPTool.encodeToJSON(tools)
print(json)
```

The `@MCPFunction` macro automatically:
- Extracts parameter names and types from the function declaration
- Captures documentation comments for descriptions
- Detects default parameter values
- Generates metadata at compile time

The `@MCPTool` macro adds a `mcpTools` computed property that collects all the function metadata and converts it to a format suitable for JSON encoding.

## JSON Output

The generated JSON includes detailed information about each function, including parameter types, descriptions, and default values:

```json
[
  {
    "description": "Adds two integers and returns their sum",
    "inputSchema": {
      "properties": {
        "a": {
          "description": "First number to add",
          "type": "number"
        },
        "b": {
          "description": "Second number to add",
          "type": "number"
        }
      },
      "required": [
        "a",
        "b"
      ],
      "type": "object"
    },
    "name": "add"
  },
  {
    "description": "Subtracts the second integer from the first and returns the difference",
    "inputSchema": {
      "properties": {
        "a": {
          "description": "Number to subtract from",
          "type": "number"
        },
        "b": {
          "default": 3,
          "description": "Number to subtract (defaults to 3)",
          "type": "number"
        }
      },
      "required": [
        "a"
      ],
      "type": "object"
    },
    "name": "subtract"
  }
]
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