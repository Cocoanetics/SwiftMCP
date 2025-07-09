# Resources

Expose read-only data through URI templates using the ``MCPResource`` macro.

## Overview

Resources allow a server to publish structured data that clients can query by URI.
Functions annotated with ``MCPResource`` describe the URI pattern and return either
plain values or ``MCPResourceContent`` such as files.

```swift
@MCPServer
actor ResourceServer {
    /// Returns information about the server
    @MCPResource("server://info")
    func info() -> String {
        "Demo server info"
    }
}
```

The macro validates that parameters match the URI placeholders and generates discovery
metadata. Parameters in the template correspond to function arguments and SwiftMCP automatically converts them from their URI representation to the declared Swift types.

Servers can also provide dynamic resources by implementing ``MCPResourceProviding``.
The demo server, for example, returns a list of files from the Downloads folder
via its ``mcpResources`` property:

```swift
extension DemoServer: MCPResourceProviding {
    var mcpResources: [any MCPResource] {
        get async { await getDynamicFileResources() }
    }
}
```

Clients can list available resources from ``MCPServer.mcpResourceTemplates``.

### Completions

When the server conforms to ``MCPCompletionProviding`` it can offer completion
suggestions for resource parameters. By default ``Bool`` and ``CaseIterable`` enum
parameters receive sensible completions.
