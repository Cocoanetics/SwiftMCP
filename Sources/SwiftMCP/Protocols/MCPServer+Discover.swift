import Foundation

// MARK: - server/discover (modern negotiation, MCP 2026-07-28 / SEP-2575)
public extension MCPServer {

    /// Builds the `serverInfo` identity advertised in an initialize or discover
    /// response. The richer `title` / `icons` / `websiteUrl` fields (introduced in
    /// `2025-06-18`, gated by `.titleField`) are included only when
    /// `includeRichIdentity` is set — legacy clients that predate them get just
    /// `name` / `version` / `description`.
    internal func buildServerInfo(includeRichIdentity: Bool) -> Implementation {
        let icons = (self as? HasIcons)?.icons ?? []
        return Implementation(
            icons: includeRichIdentity && !icons.isEmpty ? icons : nil,
            name: serverName,
            title: includeRichIdentity ? serverTitle : nil,
            version: serverVersion,
            description: serverDescription,
            websiteUrl: includeRichIdentity ? serverWebsiteUrl : nil
        )
    }

    /// Handles a `server/discover` request — the modern, stateless way a client
    /// learns which revisions the server negotiates and what it can do, without an
    /// `initialize` handshake. Reuses the same `capabilities` / `serverInfo` the
    /// initialize response carries; discovery is a modern exchange, so the rich
    /// identity fields are always included.
    internal func handleServerDiscoverRequest(
        _ request: JSONRPCMessage.JSONRPCRequestData
    ) async -> JSONRPCMessage? {
        let capabilities = await buildServerCapabilities()
        let serverInfo = buildServerInfo(includeRichIdentity: true)

        let result = DiscoverResult(
            supportedVersions: MCPProtocolVersion.supportedDescending,
            capabilities: capabilities,
            serverInfo: serverInfo
        )

        do {
            let resultDict = try JSONDictionary(encoding: result)
            return JSONRPCMessage.response(id: request.id, result: .object(resultDict))
        } catch {
            // Fallback to an empty result if encoding fails, mirroring initialize.
            return JSONRPCMessage.response(id: request.id, result: [:])
        }
    }

    /// The modern `UnsupportedProtocolVersionError`: JSON-RPC `-32004` with
    /// `data: { supported, requested }`, naming the revisions the server can
    /// negotiate so the client can retry (or fall back to the legacy handshake).
    internal func unsupportedProtocolVersionError(
        id: JSONRPCID,
        requested: String
    ) -> JSONRPCMessage {
        let supported = MCPProtocolVersion.supportedDescending.map { JSONValue.string($0) }
        return JSONRPCMessage.errorResponse(
            id: id,
            error: .init(
                code: ProtocolVersionProfile.v20260728.unsupportedVersionErrorCode,
                message: "Unsupported protocol version",
                data: .object([
                    "supported": .array(supported),
                    "requested": .string(requested)
                ])
            )
        )
    }
}
