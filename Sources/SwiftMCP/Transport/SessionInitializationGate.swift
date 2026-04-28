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
