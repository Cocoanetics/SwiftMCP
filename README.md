# SwiftMCP

SwiftMCP is a Swift package that provides a way to generate JSON descriptions of functions for use in a Multi-Call Protocol (MCP) system. It uses property wrappers to extract function metadata at runtime.

## Features

- Automatically extracts function parameter types and return types
- Generates JSON descriptions of functions
- Provides a registry for MCP functions
- Simple to use with property wrappers

## Usage

```swift
import SwiftMCP

class Calculator {
    @MCPFunction(name: "add")
    var add: (Int, Int) -> Int = { a, b in
        return a + b
    }
    
    @MCPFunction(name: "subtract")
    var subtract: (Int, Int) -> Int = { a, b in
        return a - b
    }
    
    init() {
        // Register functions with the registry
        MCPFunctionRegistry.shared.register(function: _add.projectedValue)
        MCPFunctionRegistry.shared.register(function: _subtract.projectedValue)
    }
}

// Get JSON descriptions of all registered functions
let json = MCPFunctionRegistry.shared.getAllFunctionsJSON()
print(json)
```

## Future Improvements with Swift Macros

While the current implementation uses property wrappers to extract function metadata at runtime, a more powerful approach would be to use Swift macros to extract this information at compile time. Here's how it could work:

### Using Swift Macros for Parameter Extraction

Swift macros allow for compile-time code generation and inspection. With macros, we could:

1. Automatically extract parameter names from function declarations
2. Generate more accurate type information
3. Reduce runtime overhead

#### Example Implementation

A macro-based approach would look like this:

```swift
import SwiftMCP

class Calculator {
    @MCPFunction
    var add: (Int, Int) -> Int = { a, b in
        return a + b
    }
    
    @MCPFunction
    var subtract: (Int, Int) -> Int = { a, b in
        return a - b
    }
}
```

The `@MCPFunction` macro would automatically:
- Extract parameter names (`a` and `b`) from the closure
- Generate metadata at compile time
- Register the function with the registry

#### Setting Up Swift Macros

To implement this approach, you would need to:

1. Create a macro implementation target in your package
2. Define a peer macro that analyzes function declarations
3. Use SwiftSyntax to extract parameter information from the AST

Here's a simplified example of how to set up a Swift package with macros:

```swift
// Package.swift
import PackageDescription

let package = Package(
    name: "SwiftMCP",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "SwiftMCP", targets: ["SwiftMCP"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-syntax.git", from: "509.0.0"),
    ],
    targets: [
        // Macro implementation target
        .target(
            name: "SwiftMCPMacros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax")
            ]
        ),
        
        // Library target
        .target(
            name: "SwiftMCP",
            dependencies: ["SwiftMCPMacros"]
        ),
    ]
)
```

The macro implementation would analyze the function's AST to extract parameter names and types:

```swift
import SwiftSyntax
import SwiftSyntaxMacros
import SwiftCompilerPlugin

@main
struct SwiftMCPPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        MCPFunctionMacro.self,
    ]
}

public struct MCPFunctionMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // Extract function information from the AST
        // Generate metadata declaration
        // ...
    }
}
```

## Requirements

- Swift 5.9 or later
- macOS 13.0 or later

## Installation

Add SwiftMCP to your Swift package dependencies:

```swift
dependencies: [
    .package(url: "https://github.com/yourusername/SwiftMCP.git", from: "1.0.0")
]
```

## License

This project is licensed under the MIT License - see the LICENSE file for details. 