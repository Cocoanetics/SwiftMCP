# SwiftMCP

A Swift implementation of the MCP (Multiplexed Communication Protocol) for JSON-RPC over various transports.

## Features

- Multiple transport options:
  - Standard I/O (stdio) for command-line usage
  - HTTP+SSE (Server-Sent Events) for web applications
- JSON-RPC 2.0 compliant
- Asynchronous response handling via SSE
- Built-in authorization support
- Cross-platform compatibility

## Installation

Add SwiftMCP as a dependency in your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Cocoanetics/SwiftMCP.git", branch: "main")
]
```

## Usage

### Command Line Demo

The included demo application shows how to use SwiftMCP with different transport options:

```bash
# Using stdio transport
SwiftMCPDemo --transport stdio

# Using HTTP+SSE transport
SwiftMCPDemo --transport httpsse --port 8080

# Using HTTP+SSE with authorization
SwiftMCPDemo --transport httpsse --port 8080 --token your-secret-token
```

When using HTTP+SSE transport with the `--token` option, clients must include an Authorization header with their requests:

```bash
Authorization: Bearer your-secret-token
```

## Custom Server Implementation

To implement your own MCP server:

1. Create a class conforming to `MCPServer`
2. Define your tools using `@MCPTool` attribute
3. Choose and configure a transport

Example:

```swift
class MyServer: MCPServer {
    @MCPTool
    func add(a: Int, b: Int) -> Int {
        return a + b
    }
}

// Using HTTP+SSE transport with authorization
let server = MyServer()
let transport = HTTPSSETransport(server: server, port: 8080)

// Optional: Add authorization
transport.authorizationHandler = { token in
    guard let token = token, token == "your-secret-token" else {
        return .unauthorized("Invalid token")
    }
    return .authorized
}

try transport.run()
```

## License

This project is licensed under the BSD 2-clause License - see the LICENSE file for details. 
