import Foundation
import Testing
@testable import SwiftMCP

@MCPServer(name: "EventTestServer", version: "1.0")
actor EventTestServer {
    /// A build finished.
    ///
    /// - Parameter project: Only builds of this project.
    /// - Returns: The build outcome.
    @MCPEvent(delivery: ["push", "webhook"])
    func buildFinished(project: String? = nil) -> BuildOutcome { BuildOutcome(project: "", success: true) }

    @MCPTool
    func noop() {}

    /// A heartbeat.
    @MCPEvent(delivery: EventTestServer.modes)
    func heartbeat() -> String { "" }

    static let modes = ["poll"]
}

@Schema
struct BuildOutcome: Sendable, Codable {
    let project: String
    let success: Bool
}

@MCPServer(name: "ExtensionEventServer", version: "1.0")
actor ExtensionEventServer {}

@MCPExtension("Alerts")
extension ExtensionEventServer {
    /// Something is wrong.
    @MCPEvent
    func alert(severity: String) -> BuildOutcome { BuildOutcome(project: "", success: false) }
}

@Suite("MCPEvent: events/list and capability")
struct MCPEventTests {

    private func send(_ server: any MCPServer, method: String, version: String?) async throws -> JSONRPCMessage {
        var params: JSONDictionary = [:]
        if let version {
            params["_meta"] = .object([MCPMetaKey.protocolVersion: .string(version)])
        }
        let message = JSONRPCMessage.request(id: 1, method: method, params: .object(params))
        return try #require(await RequestContext(message: message).work { _ in
            await server.handleMessage(message)
        })
    }

    @Test("events/list returns the declared event on the modern revision")
    func modernList() async throws {
        let response = try await send(EventTestServer(), method: "events/list", version: "2026-07-28")
        guard case .response(let data) = response, let result = data.result else {
            Issue.record("expected a result, got \(response)")
            return
        }
        let list = try result.decoded(EventsListResult.self)
        #expect(list.events.count == 2)
        let heartbeat = try #require(list.events.first { $0.name == "heartbeat" })
        #expect(heartbeat.delivery == ["poll"])
        #expect(heartbeat.payloadSchema != nil)
        let event = try #require(list.events.first { $0.name == "buildFinished" })
        #expect(event.name == "buildFinished")
        #expect(event.description == "A build finished.")
        #expect(event.delivery == ["push", "webhook"])
        #expect(event.inputSchema != nil)
        #expect(event.payloadSchema != nil)
    }

    @Test("events/list is -32601 on a legacy revision")
    func legacyList() async throws {
        for version in [nil, "2025-11-25"] as [String?] {
            let response = try await send(EventTestServer(), method: "events/list", version: version)
            guard case .errorResponse(let error) = response else {
                Issue.record("expected an error for \(version ?? "no version")")
                continue
            }
            #expect(error.error.code == -32601)
        }
    }

    @Test("Events extension capability is advertised only when events are declared")
    func capability() async throws {
        let withEvents = await EventTestServer().buildServerCapabilities()
        #expect(withEvents.extensions?[MCPEventsExtension.identifier] != nil)

        let without = await Calculator().buildServerCapabilities()
        #expect(without.extensions?[MCPEventsExtension.identifier] == nil)
    }

    @Test("A legacy initialize response does not advertise the events extension")
    func legacyInitializeOmitsEvents() async throws {
        let response = await EventTestServer().createInitializeResponse(id: 1, protocolVersion: "2025-11-25")
        guard case .response(let data) = response, let result = data.result else {
            Issue.record("expected a result")
            return
        }
        let capabilities = try #require(result["capabilities"])
        #expect(capabilities["extensions"]?[MCPEventsExtension.identifier] == nil)
    }

    @Test("Extension-contributed events are listed and advertised")
    func extensionEvents() async throws {
        let server = ExtensionEventServer()
        #expect(await server.buildServerCapabilities().extensions?[MCPEventsExtension.identifier] == nil)

        await ExtensionEventServer.Alerts.register(in: server)
        #expect(await server.buildServerCapabilities().extensions?[MCPEventsExtension.identifier] != nil)
        #expect(await server.mcpEventMetadata.map(\.name) == ["alert"])
    }
}
