import Foundation

enum SessionInitializationGate {
    static let rejectionMessage = "Session not initialized. Send initialize first."

    static func batchStartsWithInitialize(_ messages: [JSONRPCMessage]) -> Bool {
        guard let first = messages.first, first.isRequest else {
            return false
        }
        return first.method == "initialize"
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

    static func shouldReject(_ messages: [JSONRPCMessage], for session: Session) async -> Bool {
        !(await session.hasReceivedInitializeRequest) && !batchStartsWithInitialize(messages)
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
