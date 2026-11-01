#if Client
import Foundation

/// Multi Round-Trip Requests (SEP-2322), client side: a modern `tools/call`,
/// `resources/read` or `prompts/get` may answer `input_required`; the client
/// gathers the requested inputs and retries the original request.
extension MCPServerProxy {
    private static let inputRequiredMethods: Set<String> = ["tools/call", "resources/read", "prompts/get"]

    /// Sends `request`, completing any `input_required` rounds, and returns the
    /// final response. Requests outside modern mode or the three eligible methods
    /// are sent once, unchanged — a result without `resultType` is complete.
    internal func sendCompletingInputRounds(_ request: JSONRPCMessage) async throws -> JSONRPCMessage {
        guard negotiatedEra == .modern,
              case .request(let original) = request,
              Self.inputRequiredMethods.contains(original.method) else {
            return try await send(request)
        }

        var params = original.params?.dictionaryValue ?? [:]
        var inputResponses: JSONDictionary = [:]
        var response = try await send(request)
        var round = 0

        while let required = try inputRequiredResult(in: response) {
            round += 1
            guard round <= maxInputRounds else {
                throw MCPServerProxyError.inputRequired(
                    "\(original.method) still needed input after \(maxInputRounds) rounds"
                )
            }
            try Task.checkCancellation()

            // Responses accumulate across rounds, keyed by the server's ids.
            for (id, inputRequest) in (required.inputRequests ?? [:]).sorted(by: { $0.key < $1.key }) {
                inputResponses[id] = try await answer(inputRequest)
            }

            // Retry the original request under a new id, echoing `requestState`
            // verbatim.
            params["inputResponses"] = inputResponses.isEmpty ? nil : .object(inputResponses)
            params["requestState"] = required.requestState.map { .string($0) }
            response = try await send(
                .request(id: nextRequestID(), method: original.method, params: .object(params))
            )
        }
        return response
    }

    /// The decoded `input_required` result carried by `response`, or `nil` when
    /// the response is complete (or an error).
    private func inputRequiredResult(in response: JSONRPCMessage) throws -> InputRequiredResult? {
        guard case .response(let data) = response,
              let result = data.result?.dictionaryValue,
              result["resultType"]?.stringValue == "input_required" else {
            return nil
        }
        let required = try result.decoded(InputRequiredResult.self)
        if required.inputRequests?.isEmpty != false, required.requestState == nil {
            throw MCPServerProxyError.inputRequired(
                "input_required result carried neither inputRequests nor requestState"
            )
        }
        return required
    }

    private func answer(_ inputRequest: InputRequest) async throws -> JSONValue {
        guard let inputHandler else {
            throw MCPServerProxyError.inputRequired(
                "server requested \(inputRequest.method) but no inputHandler is set"
            )
        }
        guard inputHandler.supportedMethods.contains(inputRequest.method) else {
            throw MCPServerProxyError.inputRequired(
                "unsupported input request method \(inputRequest.method)"
            )
        }
        return try await inputHandler.handleInput(method: inputRequest.method, params: inputRequest.params)
    }
}
#endif
