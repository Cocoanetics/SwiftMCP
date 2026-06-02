// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import CompilerPluginSupport
import PackageDescription

let package = Package(
	name: "SwiftMCP",
	platforms: [
		.macOS("12.0"),
		.iOS("15.0"),
		.tvOS("15.0"),
		.watchOS("8.0"),
		.macCatalyst("15.0")
	],
	products: [
		.library(
			name: "SwiftMCP",
			targets: ["SwiftMCP"]
		),
		.library(
			name: "JSONValue",
			targets: ["JSONValue"]
		),
		// NOTE: the server demo CLIs (SwiftMCPDemo, SwiftMCPIntentsDemo) link
		// swift-nio via the `Server` trait and are appended below only where
		// swift-nio builds (everywhere except Windows). Library consumers never
		// build these demo products regardless.
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
		),
		.plugin(
			name: "SwiftMCPAggregator",
			targets: ["SwiftMCPAggregator"]
		)
	],
	traits: [
		// All feature traits are enabled by default, so existing consumers
		// (and `swift build` / `swift test` without flags) are unaffected.
		.default(enabledTraits: ["Server", "Client", "OpenAPI"]),
		// The HTTP/SSE + TCP server transports. The only feature that links
		// swift-nio, swift-crypto and swift-certificates. Disable it (e.g. on
		// Windows, or for client/tools-only consumers) to drop those deps.
		.trait(name: "Server"),
		// The MCP client (`MCPServerProxy`).
		.trait(name: "Client"),
		// OpenAPI / AI-plugin manifest models and the matching HTTP routes.
		.trait(name: "OpenAPI")
		// NOTE: AppIntents bridging is intentionally NOT a trait. The
		// `@MCPServer`/`@MCPAppIntentTool` macros expand to code in the
		// *consumer's* module that references the AppIntents glue under
		// `#if canImport(AppIntents)`. Package-trait conditions are not visible
		// in consumer modules, so a trait cannot gate that surface — and
		// `canImport(AppIntents)` already excludes it on non-Apple platforms.
	],
	dependencies: [
		.package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
		.package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0"),
		.package(url: "https://github.com/apple/swift-nio.git", from: "2.0.0"),
		.package(url: "https://github.com/swiftlang/swift-docc-plugin.git", from: "1.0.0"),
		.package(url: "https://github.com/swiftlang/swift-syntax.git", "602.0.0-latest"..<"604.0.0"),
		.package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
		.package(url: "https://github.com/apple/swift-certificates.git", from: "1.1.0"),
		.package(url: "https://github.com/Cocoanetics/SwiftCross.git", from: "1.0.0")
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
			name: "JSONValue"
		),
		.target(
			name: "SwiftMCP",
			dependencies: [
				"SwiftMCPMacros",
				"JSONValue",
				.product(name: "SwiftCross", package: "SwiftCross"),
				.product(name: "Logging", package: "swift-log"),
				// swift-nio + swift-crypto + swift-certificates are linked ONLY
				// when the `Server` trait is enabled (the HTTP/SSE transport).
				.product(name: "NIOCore", package: "swift-nio", condition: .when(traits: ["Server"])),
				.product(name: "NIOHTTP1", package: "swift-nio", condition: .when(traits: ["Server"])),
				.product(name: "NIOPosix", package: "swift-nio", condition: .when(traits: ["Server"])),
				.product(name: "NIOFoundationCompat", package: "swift-nio", condition: .when(traits: ["Server"])),
				.product(name: "Crypto", package: "swift-crypto", condition: .when(traits: ["Server"])),
				.product(name: "_CryptoExtras", package: "swift-crypto", condition: .when(traits: ["Server"])),
				.product(name: "X509", package: "swift-certificates", condition: .when(traits: ["Server"]))
			]
		),
		// NOTE: SwiftMCPDemo and SwiftMCPIntentsDemo executable targets are
		// appended after the Package initializer, guarded by `#if !os(Windows)`,
		// because they require the swift-nio-backed `Server` transports.
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
				.product(name: "SwiftCross", package: "SwiftCross"),
				.product(name: "Crypto", package: "swift-crypto", condition: .when(traits: ["Server"])),
				.product(name: "_CryptoExtras", package: "swift-crypto", condition: .when(traits: ["Server"])),
				.product(name: "X509", package: "swift-certificates", condition: .when(traits: ["Server"]))
			]
		),
		// MARK: - Prototype: per-instance @MCPExtension contributions
		.executableTarget(
			name: "SwiftMCPAggregatorTool",
			dependencies: [
				.product(name: "SwiftSyntax", package: "swift-syntax"),
				.product(name: "SwiftParser", package: "swift-syntax")
			]
		),
		.plugin(
			name: "SwiftMCPAggregator",
			capability: .buildTool(),
			dependencies: ["SwiftMCPAggregatorTool"],
			path: "Plugins/SwiftMCPAggregator"
		),
		.target(
			name: "PrototypeServerLib",
			dependencies: ["SwiftMCP"],
			path: "Demos/PrototypeServerLib",
			plugins: ["SwiftMCPAggregator"]
		),
		.target(
			name: "PrototypeExtensionsLib",
			dependencies: ["SwiftMCP", "PrototypeServerLib"],
			path: "Demos/PrototypeExtensionsLib",
			plugins: ["SwiftMCPAggregator"]
		),
		.executableTarget(
			name: "PrototypeRunner",
			dependencies: ["SwiftMCP", "PrototypeServerLib", "PrototypeExtensionsLib"],
			path: "Demos/PrototypeRunner"
		)
	]
)

// The SwiftMCPDemo / SwiftMCPIntentsDemo command-line servers use the
// swift-nio-backed HTTP/SSE, stdio and TCP transports (the `Server` trait), so
// they only build where swift-nio is available. swift-nio does not currently
// compile on Windows, so these demo executables are omitted there — which lets
// the package itself (library + tests) build and run with `--traits Client` /
// `--traits Client,OpenAPI` on Windows. Library consumers never build these
// demo products. Remove this guard once swift-nio builds on Windows.
#if !os(Windows)
package.products += [
	.executable(name: "SwiftMCPDemo", targets: ["SwiftMCPDemo"]),
	.executable(name: "SwiftMCPIntentsDemo", targets: ["SwiftMCPIntentsDemo"])
]
package.targets += [
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
	)
]
#endif
