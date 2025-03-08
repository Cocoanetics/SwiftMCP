// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "SwiftMCP",
    platforms: [.macOS(.v13)],
    products: [
        .library(
            name: "SwiftMCP",
            targets: ["SwiftMCP"]
        ),
        .executable(
            name: "SwiftMCPDemo",
            targets: ["SwiftMCPDemo"]
        ),
        // Add SwiftMCPCore as a library product
        .library(
            name: "SwiftMCPCore",
            targets: ["SwiftMCPCore"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-syntax.git", from: "600.0.1"),
    ],
    targets: [
        // Core types shared between the macro implementation and the main library
        .target(
            name: "SwiftMCPCore",
            dependencies: []
        ),
        
        // Macro implementation that performs the source transformation of a macro.
        .macro(
            name: "SwiftMCPMacros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                "SwiftMCPCore", // Add dependency on the core target
            ]
        ),

        // Library that exposes a macro as part of its API, which is used in client programs.
        .target(name: "SwiftMCP", dependencies: ["SwiftMCPMacros", "SwiftMCPCore"]),

        // A client of the library, which is able to use the macro in its own code.
        .executableTarget(name: "SwiftMCPDemo", dependencies: ["SwiftMCP", "SwiftMCPCore"]),
        
        // Test target for unit tests
        .testTarget(
            name: "SwiftMCPTests",
            dependencies: ["SwiftMCP", "SwiftMCPCore"]
        ),
    ]
)
