import Foundation

enum SessionInitializationGate {
    static let rejectionMessage = "Session not initialized. Send initialize first."

    static func batchStartsWithInitialize(_ messages: [JSONRPCMessage]) -> Bool {
        guard let first = messages.first, first.isRequest else {
            return false
        }
        return first.method == "initialize"
    }

    /// Whether the payload may proceed before `initialize`.
    ///
    /// `initialize` admits the whole batch — it opens the session, so pipelined
    /// follow-ups in the same frame are legitimately post-init. `server/discover`
    /// is sessionless and does **not** open the session, so it is admitted only as
    /// a *standalone* request: it must never carry additional, still-ungated work
    /// (e.g. a trailing `tools/call`) past the gate by leading a batch with it.
    static func batchStartsWithPreInitMethod(_ messages: [JSONRPCMessage]) -> Bool {
        if batchStartsWithInitialize(messages) {
            return true
        }
        guard messages.count == 1, let only = messages.first, only.isRequest else {
            return false
        }
        return only.method == "server/discover"
    }

    /// The `protocolVersion` declared by a leading `initialize` request, if the
    /// batch begins with one. Returns `nil` when the batch does not start with
    /// `initialize` or that request omits the field.
    static func initializeProtocolVersion(_ messages: [JSONRPCMessage]) -> String? {
        guard batchStartsWithInitialize(messages) else {
            return nil
        }
        return messages.first?.params?["protocolVersion"]?.stringValue
    }

    /// Whether the payload is a single modern-era message, identified by its
    /// `_meta` protocol version. This is the authoritative per-request era signal
    /// (matching `RequestContext.effectiveProtocolVersion`), used both to exempt
    /// modern requests from the init gate (they are stateless, with no
    /// `initialize`) and to route the modern transport.
    ///
    /// Modern applies to a request **or** a notification (both carry `_meta`).
    /// Requiring a *lone* message keeps it smuggle-safe: modern revisions forbid
    /// JSON-RPC batching, so a modern-tagged leading item can never carry sibling
    /// batch work past the gate.
    static func batchIsModern(_ messages: [JSONRPCMessage]) -> Bool {
        guard messages.count == 1, let only = messages.first,
              let version = only.params?["_meta"]?[MCPMetaKey.protocolVersion]?.stringValue else {
            return false
        }
        return MCPProtocolVersion.isModern(version)
    }

    static func shouldReject(_ messages: [JSONRPCMessage], for session: Session) async -> Bool {
        guard !(await session.hasReceivedInitializeRequest) else {
            return false
        }
        return !batchStartsWithPreInitMethod(messages) && !batchIsModern(messages)
    }

    /// Builds one error response per *request* in the batch.
    ///
    /// Notifications carry no `id` and expect no response, so a batch containing
    /// only notifications yields an empty array — the transport must stay silent
    /// rather than fabricate an unsolicited `id: nil` error.
    static func rejectionResponses(for messages: [JSONRPCMessage]) -> [JSONRPCMessage] {
        messages.compactMap { message -> JSONRPCMessage? in
            guard message.isRequest, let id = message.id else {
                return nil
            }
            return .errorResponse(id: id, error: .init(code: -32000, message: rejectionMessage))
        }
    }
}
