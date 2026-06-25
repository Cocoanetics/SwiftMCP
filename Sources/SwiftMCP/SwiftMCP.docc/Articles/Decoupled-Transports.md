# Decoupled Transports

Separate transports from the server: a transport reads its wire and calls `handle`, while `serve(over:)` owns dispatch, signal handling, and ordered shutdown.

## Overview

A transport's job is to move bytes; the server's job is to answer messages.
SwiftMCP keeps them apart with two small protocols and a single entry point on
the server:

- ``MCPDispatcher`` — the dispatch surface a transport calls: `handle` a message
  or a batch, get the reply. The initialize/batch gate lives behind it.
- ``MCPTransport`` — a `Service` that owns the wire and its sessions, and routes
  each decoded payload through an injected dispatcher.
- ``MCPServer/serve(over:gracefulShutdownSignals:logger:)`` — connects the
  dispatcher to every transport, runs them in a `ServiceGroup`, and shuts
  everything down in order.
- ``MCPServer/shutdown()`` — a lifecycle hook for releasing server-lifetime
  resources, called last.

The transport never sees the server's type; the server never sees the transport.
`serve` holds both for the duration of the call.

## The boundary

`serve` hands each transport one ``MCPDispatcher``. The transport binds the
session it owns (and, where it has one, the outbound stream scope), then calls
`handle`:

```swift
public protocol MCPDispatcher: Sendable {
    func handle(_ message: JSONRPCMessage) async -> JSONRPCMessage?
    func handle(_ batch: [JSONRPCMessage]) async -> [JSONRPCMessage]
}

public protocol MCPTransport: Service {
    func connect(to dispatcher: any MCPDispatcher)
}
```

A single message is the common case (batching was removed in MCP `2025-06-18`);
``MCPDispatcher/handle(_:)-(JSONRPCMessage)`` returns the reply, or `nil` for a
notification or accepted request. A batch round-trips as one unit through
``MCPDispatcher/handle(_:)-([JSONRPCMessage])``.

There is no inbound stream and no frame type at the boundary — the transport
reads its wire and calls a function. The **gate** (reject a non-`initialize`
request before initialization; reject a batch on a revision that removed
batching) lives inside `handle`, against `Session.current`, so a transport never
reimplements it. Dispatch (initialize, tools, resources, notifications,
`sampling`) stays inside the server; wire specifics — stdio framing, a TCP
listener with Bonjour, HTTP POST + SSE — stay inside the transport.

## Why the transport drives

Because the transport calls `handle` (rather than handing inbound frames to a
pump), it establishes whatever outbound scope a reply needs *around the call* —
no scope has to travel with the message. That collapses what used to be the
awkward case. HTTP+SSE binds a POST's per-request SSE stream inline:

```swift
// HTTP POST → its own SSE stream
await session.work(onStream: requestStreamContext) { _ in
    for reply in await dispatcher.handle(messages) {
        try? await sendJSONRPC(reply, to: streamID)
    }
}
finishSSEStream(streamID)
```

The response *and* any mid-call notifications a tool emits land on that stream,
because it is `Session.current`'s bound outbound for the duration of `handle`.
stdio and TCP, whose outbound has a single destination, bind nothing extra.

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

With the transport no longer holding the server, a server's only remaining state
is its own *domain* state. Choose the type by whether that state is shared and
mutable:

- **No domain state → `struct`.** Trivially `Sendable`; concurrent calls on an
  immutable value are safe.
- **Shared mutable state → `actor`** (or a thread-safe `class`).

```swift
@MCPServer(name: "calc")
struct Calculator {
    @MCPTool func add(a: Int, b: Int) -> Int { a + b }
}
```

## Dispatch discipline

A transport decides how it reads relative to how it dispatches — and that choice,
not the boundary, determines its concurrency:

- **In order** (stdio): fully handle one payload before reading the next. A
  client that pipes `initialize` and a follow-up in one write is never raced. The
  cost is that a tool which blocks on a server→client round-trip stalls that one
  peer until it completes.
- **Concurrent** (HTTP per-request, TCP per-connection): dispatch each payload
  without waiting, so a tool *can* make a `sampling`/`elicitation`/`roots`
  round-trip mid-call. Compliant clients wait for the `initialize` reply before
  sending more, so pre-init ordering isn't a concern in practice.

## Writing a transport

A transport stores the dispatcher, reads its wire, binds the session, and calls
`handle`:

```swift
final class MyTransport: Transport, MCPTransport, @unchecked Sendable {
    private var dispatcher: (any MCPDispatcher)?
    let session = Session(id: UUID())

    func connect(to dispatcher: any MCPDispatcher) { self.dispatcher = dispatcher }

    func run() async throws {
        await session.setTransport(self)            // outbound routes back here
        await session.work { _ in
            for await line in lines {
                let messages = try JSONRPCMessage.decodeMessages(from: line)
                let reply = messages.count == 1
                    ? await dispatcher?.handle(messages[0]).map { [$0] } ?? []
                    : await dispatcher?.handle(messages) ?? []
                if !reply.isEmpty { try await send(reply) }   // your wire
            }
        }
    }
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

The same boundary covers transports whose session isn't one socket. HTTP+SSE is
the example: a logical client is a `Mcp-Session-Id` session spread across many
HTTP requests — stateless POSTs plus SSE streams — and a POST's reply belongs to
*that* request's stream. Because the transport owns its sessions and drives
`handle`, this needs no special protocol:

- ``HTTPSSETransport`` keeps one ``Session`` per `Mcp-Session-Id`.
- Each POST binds the session and the POST's per-request SSE stream, calls
  `handle`, writes the reply to that stream, then closes it.
- Responses *and* mid-call notifications route to that stream through machinery
  the transport already owns — preserving resumable streams, request-scoped
  progress, OAuth, and legacy SSE.

## Testability

Because a transport just calls a dispatcher, it can be exercised with no sockets
and no server: hand it a stub ``MCPDispatcher``, drive its wire, and assert on
the outbound. That is exactly how SwiftMCP tests `serve(over:)` — an in-memory
transport routes canned frames through the real server-backed dispatcher and
observes the replies.

## Topics

### Protocols

- ``MCPTransport``
- ``MCPDispatcher``

### Serving

- ``MCPServer/serve(over:gracefulShutdownSignals:logger:)``
- ``MCPServer/shutdown()``

### Bundled transports

- ``StdioTransport``
- ``TCPBonjourTransport``
- ``HTTPSSETransport``
