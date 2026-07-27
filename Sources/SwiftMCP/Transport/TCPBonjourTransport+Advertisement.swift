//
//  TCPBonjourTransport+Advertisement.swift
//  SwiftMCP
//
//  What the transport publishes: the instance name it asks for, and the TXT
//  record that goes with it. Shared by the Network and stub builds, so it lives
//  outside the `canImport(Network)` split.
//

#if Server
import Foundation

extension TCPBonjourTransport {
    /// The base name before the scope decorates it.
    internal var baseInstanceName: String {
        instanceName ?? server?.serverName ?? declaredServerName ?? "MCP"
    }

    /// The instance name this transport asks mDNSResponder to register.
    ///
    /// Derived from ``baseInstanceName`` by the scope. For the local scopes a
    /// client on the same machine derives the identical string from the same base
    /// name, which is what lets a named lookup succeed without any lookup table.
    public var advertisedInstanceName: String {
        scope.instanceName(for: baseInstanceName)
    }

    /// Records what ``MCPServer/serve(over:gracefulShutdownSignals:logger:)`` knows
    /// and the transport cannot: the server's identity when this transport was built
    /// decoupled, and where a sibling transport serves the same server over HTTP.
    ///
    /// Called before the listener starts, so the TXT record is complete when the
    /// service is first published.
    internal func advertise(
        server: any MCPServer,
        httpEndpoint provider: (@Sendable () -> String?)?
    ) {
        if declaredServerName == nil { declaredServerName = server.serverName }
        if declaredServerVersion == nil { declaredServerVersion = server.serverVersion }
        if let provider { httpEndpointProvider = provider }
    }

    /// The TXT record to advertise.
    internal var txtRecord: BonjourTXTRecord {
        BonjourTXTRecord(
            serverName: server?.serverName ?? declaredServerName ?? baseInstanceName,
            serverVersion: server?.serverVersion ?? declaredServerVersion,
            protocolVersion: MCPProtocolVersion.latest,
            // A pid is only meaningful to a client on the same machine.
            processID: scope.isLocalOnly ? ProcessIdentity.processID : nil,  // meaningful only same-machine
            httpEndpoint: httpEndpoint
        )
    }
}
#endif
