# Extra Server Capabilities

SwiftMCP servers can do more than just respond to tool calls.  They can stream log messages, report progress of long running tasks and react to client supplied roots.  This article shows how to use these features.

## Progress Reporting

When a client includes a `progressToken` inside the `_meta` field of a JSON‑RPC request the server can report progress back to the client.  `RequestContext.current` exposes a `reportProgress(_:total:message:)` method which automatically sends a `notifications/progress` message using the session of the current request.

```swift
@MCPTool(description: "Performs a 30‑second countdown with progress updates")
func countdown() async -> String {
    for i in (0...30).reversed() {
        let done = Double(30 - i) / 30
        await RequestContext.current?.reportProgress(done, total: 1.0, message: "\(i) seconds remaining")
        if i > 0 { try? await Task.sleep(nanoseconds: 1_000_000_000) }
    }
    return "Countdown completed!"
}
```

## Structured Logging

`Session.current` represents the connection of the calling client.  Use `sendLogNotification(_:)` to stream structured log messages while a request is executing.  The demo server sends debug information for almost every tool:

```swift
await Session.current?.sendLogNotification(LogMessage(level: .info, data: [
    "function": "add",
    "arguments": ["a": a, "b": b]
]))
```

## Roots Support

If the client announces support for roots, the server can request the list of available filesystem roots and react to changes.  Check `Session.current.clientCapabilities.roots` before issuing requests. The demo server listens for the `roots/list_changed` notification and updates its list:

```swift
func handleRootsListChanged() async {
    guard let session = Session.current else { return }
    let updatedRoots = try? await session.listRoots()
    await session.sendLogNotification(LogMessage(level: .info, data: [
        "message": "Roots list updated",
        "roots": updatedRoots ?? []
    ]))
}
```

These capabilities let SwiftMCP servers provide rich feedback channels for clients and adapt to their environment.
