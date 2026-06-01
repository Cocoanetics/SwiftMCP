import SwiftCross

extension MCPServerProxy {
    /// Sends a JSON-RPC message to the server and waits for the response.
    public func send(_ message: JSONRPCMessage) async throws -> JSONRPCMessage {
        let messageId = message.id
        switch config {
        case .stdio, .stdioHandles, .tcp:
            return try await sendLineMessage(message, messageId: messageId)

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
        #if os(Linux)
            return try await sendStreamableRequestLinux(message, sseConfig: sseConfig)
        #else
            if #available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, macCatalyst 15.0, *) {
                return try await sendStreamableRequestApple(message, sseConfig: sseConfig)
            } else {
                throw MCPServerProxyError.unsupportedPlatform(
                    "Streamable HTTP requires macOS 12.0 or newer."
                )
            }
        #endif
    }

    private func sendLineMessage(
        _ message: JSONRPCMessage,
        messageId: JSONRPCID?
    ) async throws -> JSONRPCMessage {
        guard let messageId = messageId else {
            throw MCPServerProxyError.communicationError("Message must have an ID")
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(message)

        let messageWithNewline = data + Data("\n".utf8)
        guard let lineConnection else {
            throw MCPServerProxyError.communicationError("Not connected to line-based server")
        }

        if let streamFailure {
            throw streamFailure
        }

        await lineConnection.write(messageWithNewline)

        if let streamFailure {
            throw streamFailure
        }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<JSONRPCMessage, Error>) in
            if let streamFailure {
                continuation.resume(throwing: streamFailure)
            } else {
                responseTasks[messageId] = continuation
            }
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
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(message)
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
                if let updatedSessionID = httpResponse.value(forHTTPHeaderField: "Mcp-Session-Id") {
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
