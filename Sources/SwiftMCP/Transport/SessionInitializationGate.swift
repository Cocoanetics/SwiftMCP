import Foundation

enum SessionInitializationGate {
    static let rejectionMessage = "Session not initialized. Send initialize first."

    static func batchStartsWithInitialize(_ messages: [JSONRPCMessage]) -> Bool {
        guard let first = messages.first else {
            return false
        }

        if case .request(let request) = first {
            return request.method == "initialize"
        }

        return false
    }

    /// The `protocolVersion` declared by a leading `initialize` request, if the
    /// batch begins with one. Returns `nil` when the batch does not start with
    /// `initialize` or that request omits the field.
    static func initializeProtocolVersion(_ messages: [JSONRPCMessage]) -> String? {
        guard let first = messages.first,
              case .request(let request) = first,
              request.method == "initialize" else {
            return nil
        }

        return request.params?["protocolVersion"]?.stringValue
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
            guard case .request(let request) = message else {
                return nil
            }

            return .errorResponse(
                id: request.id,
                error: .init(code: -32000, message: rejectionMessage)
            )
        }
    }
}
