# SwiftMCP

A Swift implementation of the MCP (Model Context Protocol) for JSON-RPC over various transports.

## Features

- Multiple transport options
  - Standard I/O (stdio) for command-line usage
  - HTTP+SSE (Server-Sent Events) for web applications
- JSON-RPC 2.0 compliant with OpenAPI generation
- Built-in authorization and optional OAuth validation
- Transparent OAuth proxy mode for MCP and OpenAPI
- Cross-platform compatibility

### Server Features

- **Tools** – expose functions with `@MCPTool`
- **Resources** – publish data with `@MCPResource`
- **Prompts** – build prompts using `@MCPPrompt`
- **Utilities**
  - Progress notifications via `RequestContext.current`
  - Structured logging streamed through `Session.current`
  - Completion suggestions for parameters (defaults for `Bool` and `CaseIterable`)

### Client Features

- **Roots** – dynamic filesystem roots announced by the client
- **Sampling** – request small previews of client files

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
SwiftMCPDemo stdio

# Using HTTP+SSE transport
SwiftMCPDemo httpsse --port 8080

# Using HTTP+SSE with authorization
SwiftMCPDemo httpsse --port 8080 --token your-secret-token

# Using HTTP+SSE with OpenAPI support
SwiftMCPDemo httpsse --port 8080 --openapi

# Using HTTP+SSE with authorization and OpenAPI support
SwiftMCPDemo httpsse --port 8080 --token your-secret-token --openapi

# Using HTTP+SSE with OAuth
SwiftMCPDemo httpsse --port 8080 \
    --oauth-issuer https://example.com \
    --oauth-token-endpoint https://example.com/oauth/token \
    --oauth-introspection-endpoint https://example.com/oauth/introspect \
    --oauth-jwks-endpoint https://example.com/.well-known/jwks.json \
    --oauth-audience your-api-identifier
```

When using HTTP+SSE transport with the `--token` option, clients must include an Authorization header with their requests:

```bash
Authorization: Bearer your-secret-token
```

## OpenAPI support

The `--openapi` option enables OpenAPI endpoints for AI plugin integration. When this option is used, the server will provide an OpenAPI specification at `/openapi.json` and an AI plugin manifest at `/.well-known/ai-plugin.json`. This allows for easy integration with AI models and other tools that support OpenAPI.

## OAuth support

When `HTTPSSETransport` is configured with ``OAuthConfiguration``, the transport
validates incoming bearer tokens through the configured OAuth provider.
Validation can use an introspection endpoint or by checking JWT claims against
the provider's JWKS when introspection is not available. The transport also
serves metadata at `/.well-known/oauth-authorization-server` and
`/.well-known/oauth-protected-resource` for discovery by clients.

## Progress, Logging, Roots and Sampling

SwiftMCP can send progress updates while a tool is running, stream structured
log messages to connected clients, handle dynamic filesystem roots announced
by the client and request small data samples for preview. See the demo server for
simple implementations of these features. The <doc:ServerCapabilities> and <doc:Sampling>
articles describe the APIs in detail.

## Custom Server Implementation

To implement your own MCP server:

1. Attach the `@MCPServer` macro to a reference type like class or actor
2. Define your tools using `@MCPTool` attribute
3. Choose and configure a transport

Example:

```swift
@MCPServer
class MyServer {
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

// Or configure OAuth validation
transport.oauthConfiguration = OAuthConfiguration(
    issuer: URL(string: "https://example.com")!,
    authorizationEndpoint: URL(string: "https://example.com/authorize")!,
    tokenEndpoint: URL(string: "https://example.com/oauth/token")!,
    introspectionEndpoint: URL(string: "https://example.com/oauth/introspect")!,
    jwksEndpoint: URL(string: "https://example.com/.well-known/jwks.json")!,
    audience: "your-api-identifier",
    clientID: "client",
    clientSecret: "secret"
)

try transport.run()
```

## Typed Client Proxy

SwiftMCP can generate a typed client proxy for any server. This proxy mirrors the
`@MCPTool` signatures and forwards calls through `MCPServerProxy`. Enable it with
`generateClient: true` on the server macro.

```swift
@MCPServer(generateClient: true)
actor Calculator {
    @MCPTool
    func add(a: Int, b: Int) -> Int {
        a + b
    }
}

let url = URL(string: "http://localhost:8080/sse")!
let config = MCPServerConfig.sse(config: MCPServerSseConfig(url: url))
let proxy = MCPServerProxy(config: config)
try await proxy.connect()

let client = Calculator.Client(proxy: proxy)
let result = try await client.add(a: 2, b: 3)
```

Notes:
- Client generation is opt-in (`generateClient` defaults to `false`).
- Client methods always `throw` to surface transport or server errors.

## Documentation Extraction

The `@MCPServer` and `@MCPTool` macros extract documentation comments to describe class, parameters and return value.

## Macros Functionality

The macros in this repository provide functionality for defining and exposing tools and servers in the SwiftMCP framework. Here are the main functionalities of the macros:

* `@MCPServer`: This macro is used to define a class or actor as an MCP server. It extracts the server description from documentation comments (or the optional `description:` override). An example of its usage can be seen in the `Demos/SwiftMCPDemo/Calculator.swift` file, where the `Calculator` actor is annotated with `@MCPServer(name: "SwiftMCP Demo")`.
* `@MCPTool`: This macro is used to define functions within an MCP server that can be called as tools. It also extracts documentation comments to describe the function, parameters, and return values. Examples of its usage can be seen in the `Demos/SwiftMCPDemo/Calculator.swift` file, where various functions such as `add`, `subtract`, `testArray`, `multiply`, `divide`, `greet`, `ping`, and `noop` are annotated with `@MCPTool`.
* `@MCPResource`: This macro is used to expose read-only data through URI templates. Resources allow clients to access data using structured URIs with path and query parameters. The macro automatically generates the necessary infrastructure to match URIs against templates and extract parameters.

### Using @MCPResource

The `@MCPResource` macro allows you to expose functions as resources that can be accessed via URI patterns:

```swift
@MCPServer(name: "ResourceServer")
actor ResourceServer {
    /// Get user profile by ID
    @MCPResource("users://{user_id}/profile")
    func getUserProfile(user_id: Int) -> String {
        return "Profile for user \(user_id)"
    }
    
    /// Search users with pagination
    @MCPResource("users://search?q={query}&page={page}", mimeType: "application/json")
    func searchUsers(query: String, page: Int = 1) -> String {
        return """
        {"query": "\(query)", "page": \(page), "results": [...]}
        """
    }
}
```

Key features:
- **URI Templates**: Define patterns with placeholders in curly braces `{param}`
- **Path Parameters**: Extract values from the URI path (e.g., `/users/{id}`)
- **Query Parameters**: Extract values from query strings (e.g., `?page={page}`)
- **Optional Parameters**: Support default values for optional parameters
- **MIME Types**: Optionally specify content type with `mimeType` parameter
- **Type Safety**: Parameters are automatically converted to the correct Swift types

The server automatically provides:
- Resource discovery through `mcpResourceTemplates`
- URI matching and parameter extraction
- Type conversion and validation
- Error handling for missing or invalid parameters

These macros help in automatically generating the necessary metadata and documentation for the MCP server and its tools, making it easier to expose them for JSON-RPC communication and integration with AI models.

## License

This project is licensed under the BSD 2-clause License - see the LICENSE file for details. 
