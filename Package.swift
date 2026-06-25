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
		// The server demo CLIs run the swift-nio-backed transports under the
		// `Server` trait; their transport code is gated `#if Server`, so with
		// `Server` disabled they build as a no-op stub (no swift-nio).
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
		.package(url: "https://github.com/apple/swift-log.git", from: "1.11.0"),
		.package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0"),
		.package(url: "https://github.com/apple/swift-nio.git", from: "2.0.0"),
		// Apple's version-independent HTTP currency types (HTTPRequest.Method,
		// HTTPResponse.Status, HTTPFields). Zero-dependency and Foundation-free,
		// so it lives in the *core* target (not behind `Server`) and is shared by
		// both the client and the server transports as the single header/method/
		// status representation.
		.package(url: "https://github.com/apple/swift-http-types.git", from: "1.0.0"),
		// NIO ⇄ swift-http-types channel-handler bridge (`NIOHTTPTypesHTTP1`).
		// Server-only: it pulls swift-nio, so it is linked behind the `Server`
		// trait alongside the rest of the NIO stack.
		.package(url: "https://github.com/apple/swift-nio-extras.git", from: "1.25.0"),
		.package(url: "https://github.com/swiftlang/swift-docc-plugin.git", from: "1.0.0"),
		.package(url: "https://github.com/swiftlang/swift-syntax.git", "602.0.0-latest"..<"604.0.0"),
		// Allow both the crypto 3.x and 4.x major series. swift-certificates
		// >= 1.19 moves to crypto 4.x, so capping at < 4.0 here would make a
		// blanket `swift package update` unresolvable. crypto 4.0's only
		// breaking change is additive `CryptoError` cases, and `_RSA.Signing`
		// (the only API we use) still supports macOS 10.15 / iOS 13, so the
		// bump is safe for our macOS 12 / iOS 15 floor.
		.package(url: "https://github.com/apple/swift-crypto.git", "3.0.0"..<"5.0.0"),
		.package(url: "https://github.com/apple/swift-certificates.git", from: "1.1.0"),
		// Graceful startup/shutdown + signal handling for the server transports.
		// NIO-free (only swift-log + swift-async-algorithms), so it is linked
		// only under the `Server` trait to keep the core dependency-light.
		.package(url: "https://github.com/swift-server/swift-service-lifecycle.git", from: "2.6.0"),
		.package(url: "https://github.com/Cocoanetics/SwiftCross.git", from: "1.2.0"),
		// Foundation-only JSON family (value type + JSON Schema model + JSON-RPC
		// 2.0 envelope types) in one `JSONFoundation` module. Extracted to its own
		// repo so it can be consumed without SwiftMCP's NIO/crypto graph. Linked
		// into the core target and re-exported via Exports.swift, so `import
		// SwiftMCP` still surfaces these types.
		.package(url: "https://github.com/Cocoanetics/JSONFoundation.git", from: "1.1.0")
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
				.product(name: "JSONFoundation", package: "JSONFoundation"),
				.product(name: "SwiftCross", package: "SwiftCross"),
				.product(name: "Logging", package: "swift-log"),
				// Shared HTTP currency types — core dependency (NIO-free,
				// Foundation-free), used by both client and server.
				.product(name: "HTTPTypes", package: "swift-http-types"),
				// swift-nio + swift-crypto + swift-certificates are linked ONLY
				// when the `Server` trait is enabled (the HTTP/SSE transport).
				.product(name: "NIOCore", package: "swift-nio", condition: .when(traits: ["Server"])),
				.product(
					name: "NIOHTTPTypes",
					package: "swift-nio-extras",
					condition: .when(traits: ["Server"])
				),
				.product(
					name: "NIOHTTPTypesHTTP1",
					package: "swift-nio-extras",
					condition: .when(traits: ["Server"])
				),
				.product(name: "NIOHTTP1", package: "swift-nio", condition: .when(traits: ["Server"])),
				.product(name: "NIOPosix", package: "swift-nio", condition: .when(traits: ["Server"])),
				.product(name: "NIOFoundationCompat", package: "swift-nio", condition: .when(traits: ["Server"])),
				.product(name: "Crypto", package: "swift-crypto", condition: .when(traits: ["Server"])),
				.product(name: "_CryptoExtras", package: "swift-crypto", condition: .when(traits: ["Server"])),
				.product(name: "X509", package: "swift-certificates", condition: .when(traits: ["Server"])),
				.product(name: "ServiceLifecycle", package: "swift-service-lifecycle", condition: .when(traits: ["Server"])),
				// `UnixSignal` — the graceful-shutdown signal type named by
				// `serve(over:)` — lives in this sibling product and is not
				// re-exported by `ServiceLifecycle`, so it is linked explicitly
				// (same package, no new external dependency).
				.product(name: "UnixSignals", package: "swift-service-lifecycle", condition: .when(traits: ["Server"]))
			]
		),
		.executableTarget(
			name: "SwiftMCPDemo",
			dependencies: [
				"SwiftMCP",
				.product(name: "ArgumentParser", package: "swift-argument-parser"),
				.product(name: "ServiceLifecycle", package: "swift-service-lifecycle", condition: .when(traits: ["Server"]))
			],
			path: "Demos/SwiftMCPDemo"
		),
		.executableTarget(
			name: "SwiftMCPIntentsDemo",
			dependencies: [
				"SwiftMCP",
				.product(name: "ArgumentParser", package: "swift-argument-parser"),
				.product(name: "ServiceLifecycle", package: "swift-service-lifecycle", condition: .when(traits: ["Server"]))
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
