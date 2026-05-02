// swift-tools-version: 6.1
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
		.executable(
			name: "SwiftMCPIntentsDemo",
			targets: ["SwiftMCPIntentsDemo"]
		),
		.executable(
			name: "SwiftMCPUtility",
			targets: ["SwiftMCPUtility"]
		),
		.executable(
			name: "ProxyDemoCLI",
			targets: ["ProxyDemoCLI"]
		),
		.executable(
			name: "PrototypeRunner",
			targets: ["PrototypeRunner"]
		),
		.library(
			name: "PrototypeServerLib",
			targets: ["PrototypeServerLib"]
		),
		.library(
			name: "PrototypeExtensionsLib",
			targets: ["PrototypeExtensionsLib"]
		)
	],
	dependencies: [
		.package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
		.package(url: "https://github.com/apple/swift-argument-parser", from: "1.2.0"),
		.package(url: "https://github.com/apple/swift-nio.git", from: "2.0.0"),
		.package(url: "https://github.com/swiftlang/swift-docc-plugin.git", from: "1.0.0"),
		.package(url: "https://github.com/swiftlang/swift-syntax.git", from: "602.0.0-latest"),
		.package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
		.package(url: "https://github.com/apple/swift-certificates.git", from: "1.1.0")
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
				"SwiftMCPMacros",
				.product(name: "NIOCore", package: "swift-nio"),
				.product(name: "NIOHTTP1", package: "swift-nio"),
				.product(name: "NIOPosix", package: "swift-nio"),
				.product(name: "Logging", package: "swift-log"),
				.product(name: "NIOFoundationCompat", package: "swift-nio"),
				.product(name: "Crypto", package: "swift-crypto"),
				.product(name: "_CryptoExtras", package: "swift-crypto"),
				.product(name: "X509", package: "swift-certificates")
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
		.executableTarget(
			name: "SwiftMCPIntentsDemo",
			dependencies: [
				"SwiftMCP",
				.product(name: "ArgumentParser", package: "swift-argument-parser")
			],
			path: "Demos/SwiftMCPIntentsDemo"
		),
		.executableTarget(
			name: "SwiftMCPUtility",
			dependencies: [
				"SwiftMCP",
				"SwiftMCPUtilityCore",
				.product(name: "ArgumentParser", package: "swift-argument-parser")
			],
			path: "Utilities/SwiftMCPUtility"
		),
		.executableTarget(
			name: "ProxyDemoCLI",
			dependencies: [
				"SwiftMCP",
				.product(name: "ArgumentParser", package: "swift-argument-parser")
			],
			path: "Demos/ProxyDemoCLI"
		),
		.target(
			name: "SwiftMCPUtilityCore",
			dependencies: [
				"SwiftMCP",
				.product(name: "SwiftSyntax", package: "swift-syntax"),
				.product(name: "SwiftSyntaxBuilder", package: "swift-syntax")
			],
			path: "Utilities/SwiftMCPUtilityCore"
		),
		.testTarget(
			name: "SwiftMCPTests",
			dependencies: [
				"SwiftMCP",
				"SwiftMCPUtilityCore",
				.product(name: "Crypto", package: "swift-crypto"),
				.product(name: "_CryptoExtras", package: "swift-crypto"),
				.product(name: "X509", package: "swift-certificates")
			]
		),
		// MARK: - Prototype: per-instance @MCPExtension contributions
		.target(
			name: "PrototypeServerLib",
			dependencies: ["SwiftMCP"],
			path: "Demos/PrototypeServerLib"
		),
		.target(
			name: "PrototypeExtensionsLib",
			dependencies: ["SwiftMCP", "PrototypeServerLib"],
			path: "Demos/PrototypeExtensionsLib"
		),
		.executableTarget(
			name: "PrototypeRunner",
			dependencies: ["SwiftMCP", "PrototypeServerLib", "PrototypeExtensionsLib"],
			path: "Demos/PrototypeRunner"
		)
	]
)
