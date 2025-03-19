# Core Concepts

Learn how SwiftMCP uses documentation comments to power AI interactions.

## Overview

SwiftMCP relies heavily on documentation comments to provide meaningful information about your server and its tools to AI assistants. This article explains how the framework extracts and uses this documentation.

## Documentation Comment Syntax

SwiftMCP follows Swift's standard documentation comment syntax, which uses Markdown-flavored markup. The framework specifically looks for:

- Main description in the comment body
- Parameter descriptions using either format:
  ```swift
  - Parameters:
    - x: Description of x
    - y: Description of y
  ```
  or
  ```swift
  - Parameter x: Description of x
  - Parameter y: Description of y
  ```
- Return value documentation:
  ```swift
  - Returns: Description of return value
  ```
- Throws documentation for error cases:
  ```swift
  - Throws: Description of error conditions
  ```

You can also use other documentation extensions like:
- `- Note:`
- `- Important:`
- `- Warning:`
- `- Attention:`

For complete details on Swift's documentation comment syntax, see the [official documentation](https://github.com/swiftlang/swift/blob/main/docs/DocumentationComments.md).

## Server Documentation

When you create a server using the `@MCPServer` macro, it automatically extracts documentation from your class's comments:

```swift
/**
 A calculator server that provides basic arithmetic operations.
 
 This server exposes mathematical functions like addition, subtraction,
 multiplication and division through a JSON-RPC interface.
 */
@MCPServer
class Calculator {
    /// The name of the server, defaults to class name if not specified
    var serverName: String { "Calculator" }
    
    /// The version of the server, defaults to "1.0.0" if not specified
    var serverVersion: String { "2.0.0" }
}
```

The macro uses:
- The class's documentation comment as the server description
- The `serverName` property to identify the server (optional)
- The `serverVersion` property for versioning (optional)

## Tool Documentation

Tools are methods marked with the `@MCPTool` macro. The macro extracts documentation from method comments:

```swift
/**
 Adds two numbers and returns their sum.
 
 This function takes two integers as input and returns their arithmetic sum.
 Useful for basic addition operations.
 
 - Parameter a: The first number to add
 - Parameter b: The second number to add
 - Returns: The sum of a and b
 */
@MCPTool
func add(a: Int, b: Int) -> Int {
    a + b
}
```

The macro extracts:
- The method's main comment as the tool description
- Parameter documentation for each argument
- Return value documentation
- Any throws documentation if present

## Custom Descriptions

You can customize descriptions using the macro parameters:

```swift
@MCPTool(description: "Custom tool description")
func customTool() { }

@MCPTool(parameterDescriptions: [
    "x": "Custom description for parameter x"
])
func paramTool(x: Int) { }
```

## Importance for AI Integration

Documentation comments are crucial because:
1. They provide context to AI assistants about your server's purpose
2. They explain what each tool does and how to use it
3. They describe what parameters mean and what values are expected
4. They help AIs understand error conditions and return values

Without proper documentation:
- AIs won't understand your server's purpose
- Tools may be used incorrectly
- Parameters may receive invalid values
- Error conditions may be handled improperly

## Best Practices

1. Always document your server class with:
   - Overall purpose
   - Key features
   - Usage examples

2. Document each tool with:
   - Clear description of functionality
   - Parameter descriptions
   - Return value explanation
   - Error conditions if applicable

3. Use markdown formatting in comments for better readability

4. Include examples in complex tool documentation

5. Document any constraints or requirements

## See Also

- [Swift Documentation Comments Guide](https://github.com/swiftlang/swift/blob/main/docs/DocumentationComments.md)
- <doc:GettingStarted>
- ``MCPServer``
- ``MCPTool`` 