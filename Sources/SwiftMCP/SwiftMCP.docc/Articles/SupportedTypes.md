# Supported Types in MCP Tools

Learn about the parameter types and function signatures supported by MCP tools.

## Overview

When creating MCP tools using the `@MCPTool` macro, you can use various parameter types and function signatures. This article covers all supported types and shows examples of how to use them.

## Parameter Types

MCP tools support the following parameter types:

### Basic Types
- `Int`
- `Double`
- `Float`
- `String`
- `Bool`

### Array Types
- `[Int]`
- `[Double]`
- `[Float]`
- `[String]`
- `[Bool]`

### Enum Types
Enums without associated values that conform to `CaseIterable` and `Sendable` are supported. By default, the case labels are used as strings when the enum is serialized. You can customize the string representation by implementing `CustomStringConvertible`:

```swift
// Default behavior uses case labels
enum SearchOption: CaseIterable, Sendable {
    case all      // Will be serialized as "all"
    case unread   // Will be serialized as "unread"
    case flagged  // Will be serialized as "flagged"
}

// Custom string representation using CustomStringConvertible
enum FilterOption: CaseIterable, Sendable, CustomStringConvertible {
    case newest
    case oldest
    case popular
    
    var description: String {
        switch self {
        case .newest: return "SORT_NEW"
        case .oldest: return "SORT_OLD"
        case .popular: return "SORT_POPULAR"
        }
    }
}

// Raw values are ignored for serialization
enum Priority: String, CaseIterable, Sendable {
    case high = "H"    // Will be serialized as "high"
    case medium = "M"  // Will be serialized as "medium"
    case low = "L"     // Will be serialized as "low"
}
```

## Function Signatures

MCP tools support various function signatures:

### Basic Functions
```swift
@MCPTool
func add(a: Int, b: Int) -> Int {
    return a + b
}
```

### Async Functions
```swift
@MCPTool
func fetchData(query: String) async -> String {
    // ... async implementation
}
```

### Throwing Functions
```swift
@MCPTool
func divide(numerator: Double, denominator: Double) throws -> Double {
    guard denominator != 0 else {
        throw MathError.divisionByZero
    }
    return numerator / denominator
}
```

### Async Throwing Functions
```swift
@MCPTool
func processData(input: String) async throws -> String {
    // ... async throwing implementation
}
```

## Return Types

The return type of an MCP tool must conform to both `Sendable` and `Codable`. This includes:

- All basic types (`Int`, `Double`, `Float`, `String`, `Bool`)
- Arrays of basic types
- Custom types that conform to both protocols
- `Void` (for functions that don't return a value)

## Default Values

Parameters can have default values:

```swift
@MCPTool
func greet(name: String = "World", times: Int = 1) -> String {
    return String(repeating: "Hello, \(name)! ", count: times)
}
```

## Tips

- For enum parameters, ensure they conform to `CaseIterable` and `Sendable`
- By default, case labels are used for serialization
- You can customize enum string representation by implementing `CustomStringConvertible`
- Raw values are ignored for serialization purposes
- For custom types, ensure they conform to both `Sendable` and `Codable`
- Default values are supported for all parameter types
- Function parameters and return types must be `Sendable` to ensure thread safety

## Topics

### Related Articles
- ``MCPServer``
- ``MCPTool`` 