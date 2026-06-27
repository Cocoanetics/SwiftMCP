#if Client
import SwiftCross
import HTTPTypes

extension MCPServerProxy {
    /// Sends a JSON-RPC message to the server and waits for the response.
    public func send(_ message: JSONRPCMessage) async throws -> JSONRPCMessage {
        let messageId = message.id
        switch config {
        case .stdio, .stdioHandles, .tcp:
            return try await sendLineMessage(message)

        case .sse(let sseConfig):
            if isStreamableMCPURL(endpointURL ?? sseConfig.url) {
                return try await sendStreamable(message, sseConfig: sseConfig)
            }

            return try await sendSSEMessage(
                message,
                messageId: messageId,
                sseConfig: sseConfig
            )
        }
    }

    private func sendStreamable(
        _ message: JSONRPCMessage,
        sseConfig: MCPServerSseConfig
    ) async throws -> JSONRPCMessage {
        try await sendStreamableRequest(message, sseConfig: sseConfig)
    }

    private func sendLineMessage(
        _ message: JSONRPCMessage
    ) async throws -> JSONRPCMessage {
        guard let linePeer else {
            throw MCPServerProxyError.communicationError("Not connected to line-based server")
        }
        guard case .request(let request) = message else {
            throw MCPServerProxyError.communicationError(
                "send(_:) requires a request message with an ID"
            )
        }

        // The shared peer owns id allocation and correlation; it serializes and
        // writes through the transport. A JSON-RPC error reply comes back as a
        // thrown ``JSONRPCError`` — rewrap it into the `errorResponse` envelope the
        // proxy's callers expect, preserving the caller-facing request id.
        do {
            let result = try await linePeer.sendRequest(
                method: request.method,
                params: request.params
            )
            return .response(id: request.id, result: result)
        } catch let rpcError as JSONRPCError {
            return .errorResponse(id: request.id, error: rpcError)
        }
    }

    private func sendSSEMessage(
        _ message: JSONRPCMessage,
        messageId: JSONRPCID?,
        sseConfig: MCPServerSseConfig
    ) async throws -> JSONRPCMessage {
        guard let endpointURL = endpointURL else {
            throw MCPServerProxyError.communicationError("Not connected to server")
        }
        if let streamFailure {
            throw streamFailure
        }
        guard let messageId = messageId else {
            throw MCPServerProxyError.communicationError("Message must have an ID")
        }
        let session = URLSession(configuration: .default)
        var urlRequest = URLRequest(url: endpointURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        configureSSEPOSTRequest(&urlRequest, sseConfig: sseConfig)
        let data = try JSONRPCMessage.makeEncoder().encode(message)
        urlRequest.httpBody = data

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<JSONRPCMessage, Error>) in
            if let streamFailure {
                continuation.resume(throwing: streamFailure)
                return
            }

            responseTasks[messageId] = continuation

            Task {
                await self.dispatchSSESend(
                    session: session,
                    urlRequest: urlRequest,
                    messageId: messageId,
                    continuation: continuation
                )
            }
        }
    }

    private func dispatchSSESend(
        session: URLSession,
        urlRequest: URLRequest,
        messageId: JSONRPCID,
        continuation: CheckedContinuation<JSONRPCMessage, Error>
    ) async {
        do {
            let (responseData, response) = try await session.data(for: urlRequest)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw MCPServerProxyError.communicationError("Invalid HTTP response")
            }

            switch httpResponse.statusCode {
            case 200, 202:
                if let updatedSessionID = httpResponse.value(forHTTPField: .mcpSessionID) {
                    sessionID = updatedSessionID
                }

                // Some servers reply immediately in the HTTP body even for 202.
                if let responseMessage = try responseMessage(
                    for: messageId,
                    from: responseData
                ) {
                    if responseTasks[messageId] != nil {
                        responseTasks.removeValue(forKey: messageId)
                        continuation.resume(returning: responseMessage)
                    }
                    return
                }

                if httpResponse.statusCode == 202 {
                    return // response will arrive over SSE
                }

                let trimmed = String(data: responseData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let details = trimmed.isEmpty ? "" : ": \(trimmed)"
                let idString = messageId.stringValue
                throw MCPServerProxyError.communicationError(
                    "HTTP 200 did not include JSON-RPC response for request \(idString)\(details)"
                )
            default:
                let responseBody = String(data: responseData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let details = responseBody.isEmpty ? "" : ": \(responseBody)"
                throw MCPServerProxyError.communicationError(
                    "HTTP error \(httpResponse.statusCode)\(details)"
                )
            }
        } catch {
            if responseTasks[messageId] != nil {
                responseTasks.removeValue(forKey: messageId)
                continuation.resume(throwing: error)
            }
        }
    }
}
#endif
