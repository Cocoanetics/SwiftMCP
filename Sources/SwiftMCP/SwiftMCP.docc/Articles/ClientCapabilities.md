# Client Capabilities

Learn how to utilize client-side capabilities like roots and sampling in your MCP server.

## Overview

MCP clients can advertise various capabilities during initialization that servers can then utilize. SwiftMCP provides easy access to check these capabilities and use the associated functionality when available.

Client capabilities are accessible through `Session.current?.clientCapabilities` and include:

- **Roots**: Dynamic filesystem locations announced by the client  
- **Sampling**: LLM text generation requests the server can make to the client

In JSON, client capabilities are announced like this:

```json
{
  "capabilities": {
    "roots": {
      "listChanged": true
    },
    "sampling": {}
  }
}
```

The presence of a capability object (even if empty) indicates client support for that feature.

## Checking Client Capabilities

Always check if a client supports a capability before attempting to use it:

```swift
@MCPTool
func myTool() async throws -> String {
    guard let session = Session.current else {
        throw MCPServerError.noActiveSession
    }
    
    let capabilities = await session.clientCapabilities
    
    if capabilities?.roots != nil {
        // Client supports roots - safe to call listRoots()
        let roots = try await session.listRoots()
        // Use roots...
    }
    
    if capabilities?.sampling != nil {
        // Client supports sampling - safe to request generation
        let response = try await RequestContext.current?.sample(prompt: "Hello")
        // Use response...
    }
    
    return "Tool completed"
}
```

## Roots

Roots represent filesystem locations that the client makes available to the server. They allow servers to understand the client's working environment.

### Requesting Roots List

```swift
@MCPTool
func listClientRoots() async throws -> [String] {
    guard let session = Session.current else {
        throw MCPServerError.noActiveSession
    }
    
    // Check if client supports roots
    guard await session.clientCapabilities?.roots != nil else {
        return ["Client does not support roots"]
    }
    
    let roots = try await session.listRoots()
    return roots.map { "\(\($0.name ?? "Unnamed")): \($0.uri)" }
}
```

### Handling Roots Changes

Implement `handleRootsListChanged()` to react when the client's root list changes:

```swift
@MCPServer(name: "MyServer")
actor MyServer {
    func handleRootsListChanged() async {
        guard let session = Session.current else { return }
        
        do {
            let updatedRoots = try await session.listRoots()
            await session.sendLogNotification(LogMessage(level: .info, data: [
                "message": "Roots list updated",
                "rootCount": updatedRoots.count,
                "roots": updatedRoots.map { $0.uri.absoluteString }
            ]))
        } catch {
            await session.sendLogNotification(LogMessage(level: .warning, data: [
                "message": "Failed to retrieve updated roots list",
                "error": error.localizedDescription
            ]))
        }
    }
}
```

## Sampling

Sampling allows servers to request LLM-generated text from the client during tool execution. This enables servers to incorporate AI-generated content in their responses.

### Basic Sampling

```swift
@MCPTool
func generateSummary(data: String) async throws -> String {
    // Check if client supports sampling
    guard Session.current?.clientCapabilities?.sampling != nil else {
        return "Cannot generate summary: client does not support sampling"
    }
    
    let prompt = "Please summarize this data briefly: \(data)"
    let summary = try await RequestContext.current?.sample(prompt: prompt) ?? "No response"
    
    return "Summary: \(summary)"
}
```

### Advanced Sampling with Preferences

```swift
@MCPTool
func generateCreativeContent(topic: String) async throws -> String {
    guard Session.current?.clientCapabilities?.sampling != nil else {
        throw MCPServerError.clientHasNoSamplingSupport
    }
    
    let preferences = ModelPreferences(
        intelligencePriority: 0.8,
        costPriority: 0.2
    )
    
    let response = try await RequestContext.current?.sample(
        prompt: "Write a creative story about: \(topic)",
        systemPrompt: "You are a creative writer who writes engaging short stories.",
        modelPreferences: preferences,
        maxTokens: 500
    )
    
    return response ?? "No story generated"
}
```

## Best Practices

1. **Always check capabilities** before using client features
2. **Provide fallbacks** when capabilities are not available
3. **Handle errors gracefully** when client requests fail
4. **Use appropriate logging** to track capability usage
5. **Respect client limitations** like token limits for sampling

## Error Handling

```swift
@MCPTool
func robustTool() async -> String {
    do {
        if let capabilities = await Session.current?.clientCapabilities {
            if capabilities.sampling != nil {
                return try await RequestContext.current?.sample(prompt: "Hello") ?? "No response"
            } else {
                return "Sampling not supported by client"
            }
        } else {
            return "No client capabilities available"
        }
    } catch MCPServerError.clientHasNoSamplingSupport {
        return "Client does not support sampling"
    } catch {
        return "Error: \(error.localizedDescription)"
    }
}
```

These client capabilities enable servers to adapt their behavior based on what the client supports, creating more dynamic and capable MCP applications. 