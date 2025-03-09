# SwiftMCP JSON-RPC Demo

This demo shows how to use the SwiftMCP library to handle JSON-RPC style requests and responses.

## Running the Demo

To run the MCP demo, use the following command:

```bash
swift run SwiftMCPDemo
```

When launched, the demo will immediately send a capabilities message to stdout:

```json
{
  "json_rpc": "2.0",
  "id": 1,
  "result": {
    "meta": null,
    "protocol_version": "1.0",
    "capabilities": {
      "experimental": null,
      "logging": null,
      "prompts": null,
      "resources": null,
      "tools": [
        // Array of tools from the Calculator class
      ],
      "extra": {}
    },
    "server_info": {
      "name": "MyServer",
      "version": "1.2",
      "extra": {}
    },
    "instructions": "Welcome to MyServer!",
    "extra": {}
  }
}
```

After sending the initial capabilities message, the demo enters a continuous read loop waiting for JSON-RPC requests.

## MCP Inspector Integration

The demo is designed to work with MCP Inspector. It responds to the following methods:

- `initialize`: Returns a capabilities response with available tools

Example initialize request:

```json
{"id": 1, "method": "initialize", "params": {}}
```

The demo will respond with the same capabilities message as shown above.

## Viewing Logs

The demo logs all activity to OSLog. To view these logs in real-time, open a separate terminal window and run:

```bash
log stream --predicate 'subsystem == "com.swiftmcp.demo"' --level debug
```

This will show all debug, info, and error logs from the MCP demo.

## Example Usage

Once the demo is running, you can enter JSON-RPC requests, one per line. For example:

```json
{"id": 1, "method": "hello", "params": {"name": "Swift"}}
```

The demo will respond with:

```json
{"id":1,"result":{"message":"Hello, Swift!"}}
```

If you don't provide a name parameter, it will default to "World":

```json
{"id": 2, "method": "hello"}
```

Response:

```json
{"id":2,"result":{"message":"Hello, World!"}}
```

## Supported Methods

Currently, the demo supports the following methods:

- `hello`: A simple greeting method that takes an optional "name" parameter

## Codable Structs

The MCP protocol messages are modeled using Swift's Codable protocol. The following structs are available:

- `MCPRequest`: Represents a JSON-RPC request
- `MCPResponse`: Represents a successful JSON-RPC response
- `MCPErrorResponse`: Represents an error JSON-RPC response
- `MCPCapabilitiesResponse`: Represents the capabilities message
  - `MCPCapabilitiesResult`: Contains the capabilities information
  - `MCPCapabilities`: Defines the server capabilities (including tools)
  - `MCPServerInfo`: Contains information about the server

These structs make it easy to encode and decode JSON-RPC messages in a type-safe way.

## Extending the Demo

To add more methods, modify the `handleRequest` function in the `Sources/SwiftMCP/Models/MCPRequestResponse.swift` file.

## Exiting the Demo

The demo will continue running until the process is terminated. To exit, press Ctrl+C. 