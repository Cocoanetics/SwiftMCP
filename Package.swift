// swift-tools-version: 6.0
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
		)
	],
	dependencies: [
		.package(url: "https://github.com/apple/swift-syntax.git", from: "600.0.1"),
		.package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
		.package(url: "https://github.com/Flight-School/AnyCodable", from: "0.6.0"),
		.package(url: "https://github.com/apple/swift-argument-parser", from: "1.2.0"),
		.package(url: "https://github.com/apple/swift-nio.git", from: "2.0.0"),
		.package(url: "https://github.com/apple/swift-docc-plugin.git", from: "1.0.0")
	],
	targets: [
		.macro(
			name: "SwiftMCPMacros",
			dependencies: [
				.product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
				.product(name: "SwiftCompilerPlugin", package: "swift-syntax")
			]
		),
		.target(
			name: "SwiftMCP",
			dependencies: [
				"AnyCodable", 
				"SwiftMCPMacros",
				.product(name: "NIOCore", package: "swift-nio"),
				.product(name: "NIOHTTP1", package: "swift-nio"),
				.product(name: "NIOPosix", package: "swift-nio"),
				.product(name: "Logging", package: "swift-log"),
				.product(name: "NIOFoundationCompat", package: "swift-nio")
			]
		),
		.executableTarget(
			name: "SwiftMCPDemo",
			dependencies: [
				"SwiftMCP",
				.product(name: "ArgumentParser", package: "swift-argument-parser")
			],
			path: "Demos/SwiftMCPDemo"
		),
		.testTarget(
			name: "SwiftMCPTests",
			dependencies: ["SwiftMCP", "SwiftMCPMacros"]
		)
	]
)
