import Foundation

// MARK: - events/list (modern only, MCP Events)
extension MCPServer {

    /// Whether this server declares at least one event.
    internal func serverDeclaresEvents() async -> Bool {
        guard let provider = self as? MCPEventProviding else { return false }
        return !(await provider.mcpEventMetadata).isEmpty
    }

    /// Handles `events/list`. Events are a `2026-07-28` feature: a request that
    /// is not on a modern revision is answered as an unknown method.
    internal func handleEventsList(_ request: JSONRPCMessage.JSONRPCRequestData) async -> JSONRPCMessage {
        guard let profile = await RequestContext.current?.modernProfile, profile.has(.events) else {
            return JSONRPCMessage.errorResponse(
                id: request.id,
                error: .init(code: -32601, message: "Method not found")
            )
        }

        let metadata = await (self as? MCPEventProviding)?.mcpEventMetadata ?? []
        let result = EventsListResult(events: metadata.map(\.descriptor))
        do {
            return JSONRPCMessage.response(id: request.id, result: .object(try JSONDictionary(encoding: result)))
        } catch {
            return JSONRPCMessage.errorResponse(
                id: request.id,
                error: .init(code: -32603, message: "Internal error: \(error.localizedDescription)")
            )
        }
    }
}
