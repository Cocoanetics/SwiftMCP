# Sampling

Request small samples of client data without transferring entire files.

## Overview

SwiftMCP clients can advertise sampling functionality during initialization. When `ClientCapabilities.sampling` is present the server may ask for short snippets of a file instead of the whole resource. The demo server shows how this can be used for quick previews before loading the full content. The capability is available at runtime as `Session.current.clientCapabilities.sampling`.

The capability is defined alongside other client features:

```swift
public struct ClientCapabilities: Codable, Sendable {
    /// Present if the client supports sampling functionality.
    public var sampling: SamplingCapabilities?
    
    public struct SamplingCapabilities: Codable, Sendable {
        /// Whether this client supports sampling functionality.
        public var enabled: Bool?
    }
}
```

## Requesting Samples

A server can call into `Session.current` to request a sample of a given resource. The client responds with the requested number of bytes which can then be inspected or processed.

```swift
let preview = try await Session.current?.sample(uri: fileURL, length: 512)
```

Sampling keeps network usage low and allows tools to operate on very large files efficiently.
