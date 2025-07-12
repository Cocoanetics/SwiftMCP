# Sampling

Request LLM-generated responses from the client during tool execution.

## Overview

Sampling is a client capability that allows servers to request text generation from the client's LLM during tool execution. This enables servers to incorporate AI-generated content in their responses.

## Basic Usage

```swift
@MCPTool
func generateSummary(data: String) async throws -> String {
    // Check if client supports sampling
    guard Session.current?.clientCapabilities?.sampling != nil else {
        return "Cannot generate summary: client does not support sampling"
    }
    
    let summary = try await RequestContext.current?.sample(
        prompt: "Summarize this data briefly: \(data)"
    ) ?? "No response"
    
    return "Summary: \(summary)"
}
```

## See Also

For comprehensive information about sampling and other client capabilities, see <doc:ClientCapabilities>.
