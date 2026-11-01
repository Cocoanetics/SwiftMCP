#if Client
import Testing
import Foundation
@testable import SwiftMCP

/// A scripted line-transport server: records every message the client sends and
/// answers with whatever `handler` returns (`nil` = stay silent).
final class FakeLineServer: @unchecked Sendable {
    let clientTransport: LoopbackTransport
    private let serverTransport: LoopbackTransport
    private let lock = NSLock()
    private var messages: [JSONRPCMessage] = []
    private var task: Task<Void, Never>?

    init(handler: @escaping @Sendable (JSONRPCMessage) -> JSONRPCMessage?) {
        let pair = LoopbackTransport.pair()
        clientTransport = pair.client
        serverTransport = pair.server
        let server = pair.server
        task = Task { [weak self] in
            do {
                for try await message in server.makeInboundStream() {
                    self?.record(message)
                    if let reply = handler(message) {
                        try server.send(reply)
                    }
                }
            } catch {}
        }
    }

    deinit { task?.cancel() }

    private func record(_ message: JSONRPCMessage) {
        lock.lock()
        messages.append(message)
        lock.unlock()
    }

    var received: [JSONRPCMessage] {
        lock.lock()
        defer { lock.unlock() }
        return messages
    }

    func requests(_ method: String) -> [JSONRPCMessage.JSONRPCRequestData] {
        received.compactMap { message in
            if case .request(let request) = message, request.method == method { return request }
            return nil
        }
    }

    // MARK: Canned replies

    static func ok(_ request: JSONRPCMessage.JSONRPCRequestData, _ result: JSONDictionary) -> JSONRPCMessage {
        .response(id: request.id, result: .object(result))
    }

    static func fail(
        _ request: JSONRPCMessage.JSONRPCRequestData, _ code: Int, data: JSONValue? = nil
    ) -> JSONRPCMessage {
        .errorResponse(id: request.id, error: .init(code: code, message: "error \(code)", data: data))
    }

    static func discoverResult(_ versions: [String]) -> JSONDictionary {
        [
            "resultType": .string("complete"),
            "supportedVersions": .array(versions.map { .string($0) }),
            "capabilities": .object([:]),
            "serverInfo": .object(["name": .string("Fake"), "version": .string("1.0")])
        ]
    }

    static let initializeResult: JSONDictionary = [
        "protocolVersion": .string(MCPProtocolVersion.latest),
        "capabilities": .object([:]),
        "serverInfo": .object(["name": .string("LegacyFake"), "version": .string("1.0")])
    ]
}

struct EchoInputHandler: MCPClientInputHandler {
    func handleInput(method: String, params: JSONValue?) async throws -> JSONValue {
        .object(["action": .string("accept"), "content": .object(["method": .string(method)])])
    }
}

let modernKeys = [MCPMetaKey.protocolVersion, MCPMetaKey.clientInfo, MCPMetaKey.clientCapabilities]

func makeModernProxy(_ fake: FakeLineServer, preference: MCPClientEraPreference) async -> MCPServerProxy {
    let proxy = MCPServerProxy(config: .stdioHandles(server: ClientDiscoverTestServer()))
    await proxy.setEraPreference(preference)
    await proxy.startLinePeer(transport: fake.clientTransport)
    return proxy
}

/// A server that only speaks the modern era: it demands `_meta` on every
/// request and rejects `initialize`.
func makeModernServer(
    versions: [String] = [MCPProtocolVersion.modern, "2025-11-25"],
    tools: @escaping @Sendable (JSONRPCMessage.JSONRPCRequestData) -> JSONRPCMessage? = { request in
        FakeLineServer.ok(request, ["content": .array([.object(["type": .string("text"), "text": .string("hi")])])])
    }
) -> FakeLineServer {
    FakeLineServer { message in
        guard case .request(let request) = message else { return nil }
        switch request.method {
        case "initialize":
            return FakeLineServer.fail(request, -32601)
        case "server/discover":
            return FakeLineServer.ok(request, FakeLineServer.discoverResult(versions))
        default:
            let meta = request.params?["_meta"]?.dictionaryValue ?? [:]
            guard modernKeys.allSatisfy({ meta[$0] != nil }) else {
                return FakeLineServer.fail(request, -32602)
            }
            return tools(request)
        }
    }
}
#endif
