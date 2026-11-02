import Foundation
import Testing
@testable import SwiftMCP

/// Phase 5 (#240): per-request `logLevel`, and modern removal of `ping`,
/// `logging/setLevel` and `roots/list_changed`. Legacy is unchanged.
@Suite("Utilities era matrix")
struct UtilitiesEraMatrixTests {

    private func modernMeta(_ logLevel: String? = nil) -> JSONDictionary {
        var meta: JSONDictionary = [MCPMetaKey.protocolVersion: .string(MCPProtocolVersion.modern)]
        if let logLevel { meta[MCPMetaKey.logLevel] = .string(logLevel) }
        return meta
    }

    private func context(method: String, meta: JSONDictionary?) -> RequestContext {
        var params: JSONDictionary = [:]
        if let meta { params["_meta"] = .object(meta) }
        return RequestContext(message: .request(id: 1, method: method, params: .object(params)))
    }

    @Test("modernProfile is nil for legacy and set for modern")
    func modernProfile() async {
        let legacy = context(method: "ping", meta: nil)
        #expect(await legacy.modernProfile == nil)
        let modern = context(method: "ping", meta: modernMeta())
        #expect(await modern.modernProfile?.isModern == true)

        let session = Session(id: UUID())
        await session.setNegotiatedProtocolVersion("2025-11-25")
        let stray = await session.work { _ in await modern.modernProfile }
        #expect(stray == nil)
    }

    @Test("Modern ping and logging/setLevel are Method not found; legacy answers")
    func pingAndSetLevel() async {
        let server = Calculator()
        for method in ["ping", "logging/setLevel"] {
            let ctx = context(method: method, meta: modernMeta())
            let params: JSONDictionary = ["_meta": .object(modernMeta()), "level": .string("debug")]
            let response = await ctx.work { _ in
                await server.handleRequest(.init(id: 1, method: method, params: .object(params)))
            }
            guard case .errorResponse(let error)? = response else {
                Issue.record("expected error for \(method)"); continue
            }
            #expect(error.error.code == -32601)
        }

        let legacy = await server.handleRequest(.init(id: 2, method: "ping", params: nil))
        if case .response? = legacy {} else { Issue.record("legacy ping must answer") }
    }

    @Test("Per-request logLevel gates log notifications; legacy uses minimumLogLevel")
    func logGating() async {
        // The ephemeral session has no transport, so observe via the filter only.
        let session = Session(id: UUID())
        await session.setMinimumLogLevel(.emergency)
        let message = LogMessage(level: .warning, data: ["x": .string("y")])

        // Modern without logLevel: nothing, even though minimumLogLevel would pass.
        await session.setMinimumLogLevel(.debug)
        let noLevel = context(method: "tools/call", meta: modernMeta())
        #expect(await session.work { sess in await noLevel.shouldEmitLog(message, session: sess) } == false)
        let low = context(method: "tools/call", meta: modernMeta("info"))
        #expect(await session.work { sess in await low.shouldEmitLog(message, session: sess) } == true)
        let high = context(method: "tools/call", meta: modernMeta("error"))
        #expect(await session.work { sess in await high.shouldEmitLog(message, session: sess) } == false)

        // Legacy: session level applies.
        let legacy = context(method: "tools/call", meta: nil)
        #expect(await session.work { sess in await legacy.shouldEmitLog(message, session: sess) } == true)
        await session.setMinimumLogLevel(.error)
        #expect(await session.work { sess in await legacy.shouldEmitLog(message, session: sess) } == false)
    }
}
