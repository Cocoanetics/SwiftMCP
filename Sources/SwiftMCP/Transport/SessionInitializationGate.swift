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

    static func rejectionResponses(for messages: [JSONRPCMessage]) -> [JSONRPCMessage] {
        let requestIDs = messages.compactMap { message -> JSONRPCID? in
            guard case .request(let request) = message else {
                return nil
            }

            return request.id
        }

        if requestIDs.isEmpty {
            return [
                .errorResponse(
                    id: nil,
                    error: .init(code: -32000, message: rejectionMessage)
                )
            ]
        }

        return requestIDs.map { requestID in
            .errorResponse(
                id: requestID,
                error: .init(code: -32000, message: rejectionMessage)
            )
        }
    }
}
