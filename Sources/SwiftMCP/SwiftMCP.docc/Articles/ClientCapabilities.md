# Client Capabilities

Learn how to utilize client-side capabilities like roots and sampling in your MCP server.

## Overview

MCP clients can advertise various capabilities during initialization that servers can then utilize. SwiftMCP provides easy access to check these capabilities and use the associated functionality when available.

Client capabilities are accessible through `Session.current?.clientCapabilities` and include:

- **Roots**: Dynamic filesystem locations announced by the client  
- **Sampling**: LLM text generation requests the server can make to the client
- **Elicitation**: Interactive user input requests for structured data collection

In JSON, client capabilities are announced like this:

```json
{
  "capabilities": {
    "roots": {
      "listChanged": true
    },
    "sampling": {},
    "elicitation": {}
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
    
    if capabilities?.elicitation != nil {
        // Client supports elicitation - safe to request user input
        let schema = JSONSchema.object(JSONSchema.Object(
            properties: ["name": .string(description: "Your name")],
            required: ["name"]
        ))
        let response = try await RequestContext.current?.elicit(message: "Please enter your name", schema: schema)
        // Handle response...
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

## Elicitation

Elicitation allows servers to request structured information from users through the client during tool execution. This enables servers to gather necessary data dynamically while maintaining client control over user interactions.

### Basic Elicitation

```swift
@MCPTool
func collectUserInfo() async throws -> String {
    // Check if client supports elicitation
    guard Session.current?.clientCapabilities?.elicitation != nil else {
        return "Cannot collect user info: client does not support elicitation"
    }
    
    // Create a schema for the requested information
    let schema = JSONSchema.object(JSONSchema.Object(
        properties: [
            "name": .string(description: "Your full name"),
            "email": .string(description: "Your email address", format: "email")
        ],
        required: ["name"],
        description: "Basic contact information"
    ))
    
    let response = try await RequestContext.current?.elicit(
        message: "Please provide your contact information",
        schema: schema
    ) ?? ElicitationCreateResponse(action: .cancel)
    
    switch response.action {
    case .accept:
        if let content = response.content {
            let name = content["name"]?.value as? String ?? "Unknown"
            let email = content["email"]?.value as? String ?? "Not provided"
            return "Thank you, \(name)! Email: \(email)"
        } else {
            return "User accepted but no data provided"
        }
    case .decline:
        return "User declined to provide information"
    case .cancel:
        return "User cancelled the request"
    }
}
```

### Advanced Elicitation with Enums

```swift
@MCPTool
func collectProjectPreferences() async throws -> String {
    guard Session.current?.clientCapabilities?.elicitation != nil else {
        throw MCPServerError.clientHasNoElicitationSupport
    }
    
    let schema = JSONSchema.object(JSONSchema.Object(
        properties: [
            "projectType": .enum(values: ["web", "mobile", "desktop"], description: "Type of project"),
            "priority": .enum(values: ["speed", "cost", "quality"], description: "Main priority"),
            "hasDeadline": .boolean(description: "Has specific deadline"),
            "budget": .number(description: "Budget in USD")
        ],
        required: ["projectType", "priority"],
        description: "Project requirements and preferences"
    ))
    
    let response = try await RequestContext.current?.elicit(
        message: "Please specify your project requirements",
        schema: schema
    )
    
    guard let elicitationResponse = response else {
        return "No response received"
    }
    
    switch elicitationResponse.action {
    case .accept:
        if let content = elicitationResponse.content {
            let projectType = content["projectType"]?.value as? String ?? "unspecified"
            let priority = content["priority"]?.value as? String ?? "unspecified"
            return "Project: \(projectType), Priority: \(priority)"
        } else {
            return "Data accepted but content missing"
        }
    case .decline:
        return "User declined to specify requirements"
    case .cancel:
        return "User cancelled the requirements form"
    }
}
```

### Schema Types

Elicitation supports these JSON Schema types for flat object structures:

- **String**: `JSONSchema.string(description: "Field description", format: "email", minLength: 3, maxLength: 50)`
- **Number**: `JSONSchema.number(description: "Numeric value")`
- **Boolean**: `JSONSchema.boolean(description: "True/false value")`
- **Enum**: `JSONSchema.enum(values: ["option1", "option2"], description: "Selection")`

Supported string formats include: `email`, `uri`, `date`, `date-time`.
String constraints like `minLength` and `maxLength` are also supported for validation.

## Best Practices

1. **Always check capabilities** before using client features
2. **Provide fallbacks** when capabilities are not available
3. **Handle errors gracefully** when client requests fail
4. **Use appropriate logging** to track capability usage
5. **Respect client limitations** like token limits for sampling
6. **Handle all elicitation actions** (accept, decline, cancel) appropriately
7. **Use clear, descriptive messages** in elicitation requests
8. **Design schemas carefully** to collect only necessary information

## Error Handling

```swift
@MCPTool
func robustTool() async -> String {
    do {
        if let capabilities = await Session.current?.clientCapabilities {
            if capabilities.sampling != nil {
                return try await RequestContext.current?.sample(prompt: "Hello") ?? "No response"
            } else if capabilities.elicitation != nil {
                let schema = JSONSchema.object(JSONSchema.Object(
                    properties: ["input": .string(description: "Your input")],
                    required: ["input"]
                ))
                let response = try await RequestContext.current?.elicit(message: "Please provide input", schema: schema)
                switch response?.action {
                case .accept:
                    return "Input received via elicitation"
                case .decline:
                    return "User declined to provide input"
                case .cancel, .none:
                    return "Input request cancelled"
                }
            } else {
                return "Neither sampling nor elicitation supported by client"
            }
        } else {
            return "No client capabilities available"
        }
    } catch MCPServerError.clientHasNoSamplingSupport {
        return "Client does not support sampling"
    } catch MCPServerError.clientHasNoElicitationSupport {
        return "Client does not support elicitation"
    } catch {
        return "Error: \(error.localizedDescription)"
    }
}
```

These client capabilities enable servers to adapt their behavior based on what the client supports, creating more dynamic and capable MCP applications. 