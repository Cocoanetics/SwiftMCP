# Connection-Based Transports

Decouple transports from the server and let `serve(over:)` own the run loop, signal handling, and ordered shutdown.

## Overview

A transport is fundamentally a *source of connections*, and each connection is a
JSON-RPC duplex. SwiftMCP makes that boundary explicit with two small protocols
and a single entry point on the server:

- ``MCPConnection`` — one full-duplex JSON-RPC channel to a client, carrying
  **single messages**.
- ``MCPBatchConnection`` — an opt-in refinement for transports that also carry
  JSON-RPC *batches*.
- ``MCPTransport`` — a `Service` that yields connections.
- ``MCPServer/serve(over:gracefulShutdownSignals:logger:)`` — runs the
  transports, routes every message (or batch) through the server, and shuts
  everything down in order.
- ``MCPServer/shutdown()`` — a lifecycle hook for releasing server-lifetime
  resources, called last.

The transport never sees the server, and the server never sees the transport.
`serve` owns both for the duration of the call.

## The boundary

The base connection deals in **single messages** — the common case, and the only
shape MCP `2025-06-18` and later use (that revision removed JSON-RPC batching):

```swift
public protocol MCPConnection: Sendable {
    var inbound: AsyncStream<JSONRPCMessage> { get }     // JSON-RPC in
    func send(_ message: JSONRPCMessage) async throws    // JSON-RPC out
}

public protocol MCPTransport: Service {
    var connections: AsyncStream<MCPConnection> { get }
}
```

A transport that must still carry batches — a top-level JSON array that has to
round-trip as one payload — conforms to ``MCPBatchConnection`` instead, which
adds a whole-frame interface. Conformers implement only the batch members; the
single-message requirements are derived for free:

```swift
public protocol MCPBatchConnection: MCPConnection {
    var inboundBatches: AsyncStream<[JSONRPCMessage]> { get }
    func send(_ batch: [JSONRPCMessage]) async throws
}
```

`serve` routes a plain ``MCPConnection`` one message at a time through
``MCPServer/handleMessage(_:)``, and a ``MCPBatchConnection`` whole-frame through
``MCPServer/processBatch(_:ignoringEmptyResponses:)`` — applying the same
version-gated batch reject the byte-stream transports use, so a client on a
no-batching revision that sends a batch gets a `-32600` error. The bundled
``StdioTransport`` and ``TCPBonjourTransport`` are batch-capable, because a stdin
line or TCP frame may be a JSON array.

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

Conform to ``MCPTransport``: accept connections however the wire dictates, wrap
each as an ``MCPConnection``, and yield it to ``MCPTransport/connections``. Run
until graceful shutdown in `Service.run()`, then finish the connections stream
(and each connection's `inbound`) so routing unwinds.

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

Stdio and TCP map one socket to one connection. HTTP+SSE doesn't: a logical
client is a `Mcp-Session-Id` session spread across many HTTP requests — stateless
POSTs plus SSE streams — and a POST's reply belongs to *that* request's stream.
For transports like this, the connection (not `serve`) owns the `Session` and the
per-request reply routing, via ``MCPScopedConnection``:

- The transport surfaces one ``MCPScopedConnection`` per session.
- Each POST is delivered as an ``MCPInboundFrame`` whose ``MCPInboundFrame/within``
  scope binds the right `Session.current` and the POST's SSE stream, then tears it
  down.
- `serve` becomes a pure pump: it dispatches each pre-gated frame inside `within`,
  so responses *and* mid-call notifications route to the correct stream through
  machinery the transport already owns.

This is how ``HTTPSSETransport`` conforms to ``MCPTransport`` while preserving
resumable streams, request-scoped progress, OAuth, and the rest.

## Testability

Because a connection is just two JSON-RPC streams and a transport is just a
source of them, both can be exercised with no sockets and no server: feed a
canned ``MCPConnection/inbound`` stream and assert on what
`send(_:)` receives. That is exactly how SwiftMCP tests
`serve(over:)` itself.

## Topics

### Protocols

- ``MCPConnection``
- ``MCPBatchConnection``
- ``MCPScopedConnection``
- ``MCPInboundFrame``
- ``MCPTransport``

### Serving

- ``MCPServer/serve(over:gracefulShutdownSignals:logger:)``
- ``MCPServer/shutdown()``

### Bundled transports

- ``StdioTransport``
- ``TCPBonjourTransport``
- ``HTTPSSETransport``
