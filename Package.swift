// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import CompilerPluginSupport
import PackageDescription

let package = Package(
	name: "SwiftMCP",
	platforms: [
		.macOS("11.0"),
		.iOS("14.0"),
		.tvOS("14.0"),
		.watchOS("7.0"),
		.macCatalyst("14.0")
	],
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
		.package(url: "https://github.com/Flight-School/AnyCodable", from: "0.6.0"),
		.package(url: "https://github.com/apple/swift-argument-parser", from: "1.2.0"),
		.package(url: "https://github.com/apple/swift-nio.git", from: "2.0.0"),
	],
	targets: [
		// Library that exposes a macro as part of its API, which is used in client programs.
		.target(
			name: "SwiftMCP",
			dependencies: [
				"AnyCodable", 
				"SwiftMCPMacros",
				.product(name: "NIOCore", package: "swift-nio"),
				.product(name: "NIOHTTP1", package: "swift-nio"),
				.product(name: "NIOPosix", package: "swift-nio"),
				.product(name: "NIOFoundationCompat", package: "swift-nio"),
			]
		),
		
		// A client of the library, which is able to use the macro in its own code.
		.executableTarget(
			name: "SwiftMCPDemo",
			dependencies: [
				"SwiftMCP",
				.product(name: "ArgumentParser", package: "swift-argument-parser")
			]
		),
		
		// Test target for unit tests
		.testTarget(
			name: "SwiftMCPTests",
			dependencies: ["SwiftMCP", "SwiftMCPMacros"]
		),
		
		// The implementation of the macro, which is a separate target so that it
		// can be compiled separately from the rest of the code.
			.macro(
				name: "SwiftMCPMacros",
				dependencies: [
					.product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
					.product(name: "SwiftCompilerPlugin", package: "swift-syntax")
				]
			)
	]
)
