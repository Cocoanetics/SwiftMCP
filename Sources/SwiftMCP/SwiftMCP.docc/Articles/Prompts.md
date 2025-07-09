# Prompts

Define reusable prompt builders with the ``MCPPrompt`` macro.

## Overview

A prompt is a function that returns text or ``PromptMessage`` objects for use with
language models. ``MCPPrompt`` gathers the parameter information so prompts can be
called through the same JSON-RPC mechanism as tools.

```swift
@MCPServer
actor DemoServer {
    /// Produce a greeting
    @MCPPrompt()
    func hello(name: String) -> String {
        "Hello \(name)!"
    }
}
```

Prompts participate in completion just like tools and resources. ``CaseIterable`` enums
and ``Bool`` parameters automatically receive sensible completions. Implement
``MCPCompletionProviding`` to offer suggestions for other parameters.
