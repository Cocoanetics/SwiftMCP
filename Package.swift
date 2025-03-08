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
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-syntax.git", from: "600.0.1"),
    ],
    targets: [
        // Macro implementation that performs the source transformation of a macro.
        .macro(
            name: "SwiftMCPMacros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ]
        ),

        // Library that exposes a macro as part of its API, which is used in client programs.
        .target(name: "SwiftMCP", dependencies: ["SwiftMCPMacros"]),

        // A client of the library, which is able to use the macro in its own code.
        .executableTarget(name: "SwiftMCPDemo", dependencies: ["SwiftMCP"]),
        
        // Test target for unit tests
        .testTarget(
            name: "SwiftMCPTests",
            dependencies: ["SwiftMCP"]
        ),
    ]
)
