# Getting Started with SwiftMCP

Create your first MCP server in minutes.

## Overview

SwiftMCP makes it easy to build Model Control Protocol (MCP) servers that can interact with AI models. This guide will help you get started with the basics.

## Installation

Add SwiftMCP to your project using Swift Package Manager:

```swift
dependencies: [
    .package(url: "https://github.com/yourusername/SwiftMCP.git", from: "1.0.0")
]
```

## Basic Usage

1. Create a new Swift file for your server:

```swift
import SwiftMCP

@MCPServer(version: "1.0.0")
struct Calculator {
    @MCPTool(description: "Adds two numbers together")
    func add(a: Double, b: Double) -> Double {
        return a + b
    }
}
```

2. Run your server:

```swift
import SwiftMCP

let calculator = Calculator()
let transport = StdioTransport()

try await transport.start(server: calculator)
```

## Next Steps

- Follow the <doc:BuildingAnMCPServer> tutorial to learn more advanced features
- Explore the API documentation for detailed information about available options
- Check out the example projects in the repository 