#if Client
import Foundation

/// Era selection: probe `server/discover`, pick a modern revision, or fall back
/// to the legacy `initialize` handshake (see ``MCPClientEraPreference``).
extension MCPServerProxy {
    private struct EraProbeTimeout: Error {}

    private enum EraProbeOutcome {
        case modern
        case legacy(reuseConnection: Bool)
    }

    /// The modern revisions this client implements. Private to the client — it is
    /// only used once a server's `server/discover` selects it, never advertised.
    private static let clientModernVersions: Set<String> = [MCPProtocolVersion.modern]

    /// JSON-RPC codes a legacy server may answer a modern probe with.
    private static let notModernCodes: Set<Int> = [-32601, -32004, -32600, -32602, -32000]

    /// Brings the connection up in the negotiated era: modern (no handshake) or
    /// legacy (`initialize` + `notifications/initialized`).
    ///
    /// - Parameter reconnect: Re-creates the line transport (re-spawning a stdio
    ///   server). Used after a timed-out probe, since a legacy server may have
    ///   wedged on the unknown pre-`initialize` method.
    internal func establishConnection(
        clientName: String,
        clientVersion: String,
        supportsModern: Bool = true,
        reconnect: (@Sendable () async throws -> Void)? = nil
    ) async throws {
        clientIdentity = (clientName, clientVersion)
        negotiatedEra = nil
        modernProtocolVersion = nil
        headerParameters = nil

        if eraPreference != .legacy {
            guard supportsModern else {
                if eraPreference == .modern {
                    throw MCPServerProxyError.unsupportedProtocolVersion(supported: [])
                }
                try await initializeLegacy(clientName: clientName, clientVersion: clientVersion)
                return
            }
            switch try await probeModernEra() {
            case .modern:
                refreshListenSubscription()
                return
            case .legacy(let reuseConnection):
                if !reuseConnection, let reconnect {
                    try await reconnect()
                }
            }
        }
        try await initializeLegacy(clientName: clientName, clientVersion: clientVersion)
    }

    private func initializeLegacy(clientName: String, clientVersion: String) async throws {
        try await initialize(clientName: clientName, clientVersion: clientVersion)
        negotiatedEra = .legacy
    }

    private func probeModernEra() async throws -> EraProbeOutcome {
        // The probe is itself a modern request: tentatively select the era so it
        // carries `_meta` and (on HTTP) the modern headers and no session id.
        negotiatedEra = .modern
        modernProtocolVersion = MCPProtocolVersion.modern
        let request = JSONRPCMessage.request(id: nextRequestID(), method: "server/discover", params: nil)

        let response: JSONRPCMessage
        do {
            response = try await sendProbe(request)
        } catch {
            resetEraSelection()
            return try legacyFallback(after: error)
        }

        switch response {
        case .response(let data):
            guard let result = data.result?.dictionaryValue,
                  let discovered = try? result.decoded(DiscoverResult.self) else {
                resetEraSelection()
                throw MCPServerProxyError.communicationError("Invalid server/discover response")
            }
            lastDiscover = discovered
            let mutual = discovered.supportedVersions
                .filter { MCPProtocolVersion.isModern($0) && Self.clientModernVersions.contains($0) }
                .max()
            guard let version = mutual else {
                resetEraSelection()
                if eraPreference == .modern {
                    throw MCPServerProxyError.unsupportedProtocolVersion(supported: discovered.supportedVersions)
                }
                return .legacy(reuseConnection: true)
            }
            modernProtocolVersion = version
            applyDiscoverResult(discovered)
            return .modern

        case .errorResponse(let data):
            let error = data.error
            let typed = typedModernError(error)
            resetEraSelection()
            guard Self.notModernCodes.contains(error.code) else {
                throw typed ?? MCPServerProxyError.communicationError(error.message)
            }
            if eraPreference == .modern {
                let supported = (typed.flatMap { error -> [String]? in
                    if case .unsupportedProtocolVersion(let list) = error { return list }
                    return nil
                }) ?? []
                throw MCPServerProxyError.unsupportedProtocolVersion(supported: supported)
            }
            return .legacy(reuseConnection: true)

        default:
            resetEraSelection()
            throw MCPServerProxyError.communicationError("Invalid server/discover response")
        }
    }

    private func resetEraSelection() {
        negotiatedEra = nil
        modernProtocolVersion = nil
    }

    /// Decides whether a failed probe means "this server is legacy". Timeouts and
    /// auth/transport errors surface instead of silently downgrading — except on
    /// line transports, where a legacy server simply never answers the unknown
    /// method.
    private func legacyFallback(after error: Error) throws -> EraProbeOutcome {
        let strict = eraPreference == .modern
        if error is EraProbeTimeout {
            guard !strict else {
                throw MCPServerProxyError.communicationError("server/discover timed out")
            }
            if case .stdio = config {
                return .legacy(reuseConnection: false)
            }
            return .legacy(reuseConnection: true)
        }
        if case MCPServerProxyError.httpStatus(let status, _) = error, [400, 404, 405].contains(status) {
            if strict {
                throw MCPServerProxyError.unsupportedProtocolVersion(supported: [])
            }
            return .legacy(reuseConnection: true)
        }
        throw error
    }

    /// Sends the probe; line transports race it against ``eraProbeTimeout``.
    private func sendProbe(_ request: JSONRPCMessage) async throws -> JSONRPCMessage {
        if case .sse = config {
            return try await send(request)
        }
        let nanoseconds = UInt64(max(eraProbeTimeout, 0) * 1_000_000_000)
        return try await withThrowingTaskGroup(of: JSONRPCMessage.self) { group in
            group.addTask { try await self.send(request) }
            group.addTask {
                try await Task.sleep(nanoseconds: nanoseconds)
                throw EraProbeTimeout()
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else {
                throw EraProbeTimeout()
            }
            return first
        }
    }

    private func applyDiscoverResult(_ result: DiscoverResult) {
        serverName = result.serverInfo.name
        serverVersion = result.serverInfo.version
        serverDescription = result.serverInfo.description
        serverTitle = result.serverInfo.title
        serverWebsiteUrl = result.serverInfo.websiteUrl
        serverIcons = result.serverInfo.icons ?? []
        serverInstructions = result.instructions
        serverCapabilities = result.capabilities
        if service == nil {
            service = serverName
        }
    }

    #if os(macOS) || os(Linux) || os(Windows)
    /// Spawns the server over JSONFoundation's swift-subprocess stdio transport —
    /// the shared, lock-free child-process transport LSP and SwiftACP use. The
    /// command keeps SwiftMCP's `/bin/zsh -lc` wrapping so a login shell resolves
    /// PATH and the user's environment.
    internal func makeStdioTransport(_ stdioConfig: MCPServerStdioConfig) -> any JSONRPCMessageTransport {
        let shellCommand = ([stdioConfig.command] + stdioConfig.args)
            .joined(separator: " ")
        let launch = ProcessLaunch(
            executable: "/bin/zsh",
            arguments: ["-lc", shellCommand],
            environment: stdioConfig.environment,
            workingDirectory: stdioConfig.workingDirectory
        )
        // JSONRPCSubprocess's, not SwiftMCP's server-side StdioTransport.
        return JSONRPCSubprocess.StdioTransport(
            endpoint: .childProcess(launch),
            framing: LineFraming()
        )
    }

    internal func restartStdioPeer(_ stdioConfig: MCPServerStdioConfig) async {
        await linePeer?.close()
        linePeer = nil
        lineTransport = nil
        await startLinePeer(transport: makeStdioTransport(stdioConfig))
    }
    #endif
}
#endif
