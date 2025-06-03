import Foundation

public extension MCPServer {
    /// Processes a batch of JSON-RPC messages sequentially.
    /// - Parameters:
    ///   - messages: The messages to handle.
    ///   - ignoringEmptyResponses: If true, `.response` messages with an empty result are ignored.
    /// - Returns: An array of response messages.
    func processBatch(_ messages: [JSONRPCMessage], ignoringEmptyResponses: Bool = false) async -> [JSONRPCMessage] {
        var responses: [JSONRPCMessage] = []
        for message in messages {
            if ignoringEmptyResponses,
               case .response(let responseData) = message,
               let result = responseData.result,
               result.isEmpty {
                continue
            }

            if let response = await handleMessage(message) {
                responses.append(response)
            }
        }
        return responses
    }
}
