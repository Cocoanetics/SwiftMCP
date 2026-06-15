import Foundation
import Testing
@testable import SwiftMCP

@Suite("RequestContext protocol-version seam")
struct RequestContextProtocolVersionTests {

    private func makeContext(meta: JSONDictionary?) -> RequestContext {
        var params: JSONDictionary = [:]
        if let meta {
            params["_meta"] = .object(meta)
        }
        let message = JSONRPCMessage.request(
            id: 1,
            method: "tools/call",
            params: params.isEmpty ? nil : params
        )
        return RequestContext(message: message)
    }

    @Test("Meta parses the modern _meta identity keys")
    func metaParsesModernKeys() {
        let context = makeContext(meta: [
            MCPMetaKey.protocolVersion: .string("2026-07-28"),
            MCPMetaKey.clientInfo: .object(["name": .string("ExampleClient"), "version": .string("1.0.0")]),
            MCPMetaKey.clientCapabilities: .object([:]),
            MCPMetaKey.logLevel: .string("warning")
        ])

        #expect(context.meta?.protocolVersion == "2026-07-28")
        #expect(context.meta?.clientInfo?.name == "ExampleClient")
        #expect(context.meta?.clientInfo?.version == "1.0.0")
        #expect(context.meta?.clientCapabilities != nil)
        #expect(context.meta?.logLevel == .warning)
    }

    @Test("Modern request resolves to the modern profile without a session")
    func modernResolution() async {
        let context = makeContext(meta: [MCPMetaKey.protocolVersion: .string("2026-07-28")])

        #expect(await context.effectiveProtocolVersion == "2026-07-28")
        let profile = await context.protocolProfile
        #expect(profile.isModern)
        #expect(profile.has(.mrtr))
        #expect(profile.has(.initializeHandshake) == false)
    }

    @Test("requestedLogLevel comes from _meta, nil when absent")
    func requestedLogLevel() {
        let withLevel = makeContext(meta: [MCPMetaKey.logLevel: .string("debug")])
        #expect(withLevel.requestedLogLevel == .debug)

        let withoutLevel = makeContext(meta: [MCPMetaKey.protocolVersion: .string("2026-07-28")])
        #expect(withoutLevel.requestedLogLevel == nil)
    }

    @Test("Absent _meta falls back to latest")
    func defaultResolution() async {
        let context = makeContext(meta: nil)
        #expect(await context.effectiveProtocolVersion == MCPProtocolVersion.latest)
        #expect(await context.protocolProfile.era == .legacy)
    }

    @Test("Legacy request resolves from the session-negotiated version")
    func legacyResolution() async {
        let session = Session(id: UUID())
        await session.setNegotiatedProtocolVersion("2025-06-18")
        // No protocolVersion in _meta -> resolution falls back to the session.
        let context = makeContext(meta: ["progressToken": .string("p")])

        await session.work { _ in
            #expect(await context.effectiveProtocolVersion == "2025-06-18")
            let profile = await context.protocolProfile
            #expect(profile.era == .legacy)
            #expect(profile.has(.jsonRPCBatching) == false)  // removed in 2025-06-18
        }
    }

    @Test("_meta wins over the session when both are present")
    func metaWinsOverSession() async {
        let session = Session(id: UUID())
        await session.setNegotiatedProtocolVersion("2025-06-18")
        let context = makeContext(meta: [MCPMetaKey.protocolVersion: .string("2026-07-28")])

        await session.work { _ in
            #expect(await context.effectiveProtocolVersion == "2026-07-28")
            #expect(await context.protocolProfile.isModern)
        }
    }
}
