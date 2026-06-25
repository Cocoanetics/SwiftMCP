# Connection-Based Transports

Decouple transports from the server and let `serve(over:)` own the run loop, signal handling, and ordered shutdown.

## Overview

A transport is fundamentally a *source of connections*, and each connection is a
JSON-RPC duplex that owns its session. SwiftMCP makes that boundary explicit with
two small protocols and a single entry point on the server:

- ``MCPConnection`` — one full-duplex JSON-RPC channel to a client; owns its
  ``Session`` and yields ``MCPInboundFrame``s. ``BasicConnection`` is the
  ready-made shape for a one-socket transport.
- ``MCPTransport`` — a `Service` that yields connections.
- ``MCPServer/serve(over:gracefulShutdownSignals:logger:)`` — a pump that runs
  the transports, routes every frame through the server, and shuts everything
  down in order.
- ``MCPServer/shutdown()`` — a lifecycle hook for releasing server-lifetime
  resources, called last.

The transport never sees the server, and the server never sees the transport.
`serve` owns both for the duration of the call.

## The boundary

There is one connection protocol. A connection **owns its `Session`** and hands
`serve` inbound frames, each carrying the outbound scope for its reply:

```swift
public protocol MCPConnection: Sendable {
    var session: Session { get }                      // the connection owns it
    var inbound: AsyncStream<MCPInboundFrame> { get }  // frames + per-frame scope
    func send(_ frame: [JSONRPCMessage]) async throws  // JSON-RPC out
}

public protocol MCPTransport: Service {
    var connections: AsyncStream<MCPConnection> { get }
}
```

The unit of transfer is a *frame* — an array of ``JSONRPCMessage``. A single
message is a one-element frame; a JSON-RPC batch is a multi-element frame that
round-trips as one payload (batching was removed in MCP `2025-06-18`, so most
frames are single).

`serve` is a **pure pump** over that one shape: it binds the connection's
session, gates each frame (rejecting pre-initialize requests, and batches on
no-batching revisions with `-32600`), and runs
``MCPServer/processBatch(_:ignoringEmptyResponses:)`` inside the frame's
``MCPInboundFrame/within`` scope — never minting a session of its own. The gate
runs sequentially in the read loop while dispatch runs concurrently, so a tool
awaiting a server→client response (`sampling`/`elicitation`/`roots`) never blocks
reading that very response.

Wire specifics — stdio framing, a TCP listener with Bonjour advertising, HTTP
POST + SSE — stay inside the transport. Dispatch (initialize, tools, resources,
notifications, sampling) stays inside the server.

## Serving

Hand the server one or more transports and let it run:

```swift
let transport = TCPBonjourTransport(serviceName: "acpx")   // no server reference
try await server.serve(over: [transport], logger: log)
```

That single call replaces the hand-built `ServiceGroup` consumers used to write:

```swift
// Before — every consumer re-derived this, including the shutdown details.
let transport = TCPBonjourTransport(server: server, serviceName: "acpx")
let group = ServiceGroup(configuration: .init(
    services: [.init(service: transport,
                     successTerminationBehavior: .gracefullyShutdownGroup,
                     failureTerminationBehavior: .gracefullyShutdownGroup)],
    gracefulShutdownSignals: [.sigterm, .sigint],
    logger: log))
try await group.run()
```

### Shutdown correctness, owned once

`serve` registers every transport with both `successTerminationBehavior` and
`failureTerminationBehavior` set to `.gracefullyShutdownGroup`. The default
failure behavior (`.cancelGroup`) cancels every service *concurrently* when one
transport fails, which can race ordered teardown — a successor grabbing a lock
while the previous owner is still draining. Graceful failure handling instead
unwinds the group in reverse-registration order.

``MCPServer/shutdown()`` runs **after** the transport group has fully stopped, so
your teardown is always the last step — on a graceful signal, on a transport
finishing, and on a transport throwing alike:

```swift
@MCPServer(name: "acpx")
actor Daemon {
    func shutdown() async {
        await closeLiveAgents()   // no orphaned subprocesses
        releaseSingletonLock()    // safe: transports already drained
    }
}
```

## Value-type servers

With the transport no longer holding the server, and per-connection state living
in the connection layer, a server's only remaining state is its own *domain*
state. Choose the type by whether that state is shared and mutable:

- **No domain state → `struct`.** Trivially `Sendable`; concurrent calls on an
  immutable value are safe.
- **Shared mutable state → `actor`** (or a thread-safe `class`).

```swift
@MCPServer(name: "calc")
struct Calculator {
    @MCPTool func add(a: Int, b: Int) -> Int { a + b }
}
```

## Writing a transport

For a transport that is a single duplex (stdio, TCP, an in-memory pipe), reach
for ``BasicConnection`` — it owns a fresh session and `serve` wires its outbound
back to you, so you only feed decoded frames and write bytes:

```swift
func run() async throws {
    let connection = BasicConnection { frame in
        try await writeLine(JSONRPCFrame.encode(frame))   // your wire
    }
    connectionsContinuation.yield(connection)
    for try await line in lines { connection.deliver(try JSONRPCMessage.decodeMessages(from: line)) }
    connection.close()   // on EOF
}
```

All three bundled transports support both modes: construct them with a server
(`init(server:)`) to run them yourself, or server-less
(`StdioTransport()` / `TCPBonjourTransport(serviceName:)` / `HTTPSSETransport(host:port:)`)
to hand them to `serve`:

```swift
let http = HTTPSSETransport(host: "0.0.0.0", port: 8080)   // no server
let tcp  = TCPBonjourTransport(serviceName: "acpx")
try await server.serve(over: [http, tcp], logger: log)     // one call, both transports
```

## Session-spanning transports

The same one protocol covers transports whose session isn't one socket. HTTP+SSE
is the example: a logical client is a `Mcp-Session-Id` session spread across many
HTTP requests — stateless POSTs plus SSE streams — and a POST's reply belongs to
*that* request's stream. Because a connection already **owns its session** and
supplies a per-frame ``MCPInboundFrame/within`` scope, this needs no special
protocol:

- ``HTTPSSETransport`` surfaces one ``MCPConnection`` per `Mcp-Session-Id` session
  (whose session is the transport's own).
- Each POST is delivered as a frame whose `within` binds the POST's per-request
  SSE stream, then finishes it.
- `serve` pumps it like any other connection; responses *and* mid-call
  notifications route to that stream through machinery the transport already owns
  — preserving resumable streams, request-scoped progress, OAuth, and legacy SSE.

## Testability

Because a connection is just an inbound stream and a `send`, it can be exercised
with no sockets and no server: feed a canned ``MCPConnection/inbound`` and assert
on what `send(_:)` receives. That is exactly how SwiftMCP tests `serve(over:)`.

## Topics

### Protocols

- ``MCPConnection``
- ``MCPInboundFrame``
- ``BasicConnection``
- ``MCPTransport``

### Serving

- ``MCPServer/serve(over:gracefulShutdownSignals:logger:)``
- ``MCPServer/shutdown()``

### Bundled transports

- ``StdioTransport``
- ``TCPBonjourTransport``
- ``HTTPSSETransport``
