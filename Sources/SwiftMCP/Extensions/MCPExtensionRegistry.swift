//
//  MCPExtensionContribution.swift
//  SwiftMCP
//
//  Per-instance contribution from a `@MCPExtension(_)`-annotated extension.
//  Each `@MCPServer` type stores a private array of these on every instance.
//  Registration is per-instance: `MyServer.Calendar.register(in: server)`
//  appends to `server.__mcpExtensionContributions`. No global state.
//

import Foundation

/// One block of tools contributed by a `@MCPExtension` to a server instance.
///
/// `metadata` lists every tool the extension exposes; `dispatcher` is the
/// nested enum's `static func callTool(_:on:arguments:)` reference. The
/// dispatcher is an unbound static function — it captures nothing, so there
/// is no retain cycle between the server and its dispatchers.
public struct MCPExtensionContribution<Server> {
    public typealias Dispatcher = (String, Server, JSONDictionary) async throws -> Encodable & Sendable

    public let metadata: [MCPToolMetadata]
    public let dispatcher: Dispatcher

    public init(metadata: [MCPToolMetadata], dispatcher: @escaping Dispatcher) {
        self.metadata = metadata
        self.dispatcher = dispatcher
    }
}
