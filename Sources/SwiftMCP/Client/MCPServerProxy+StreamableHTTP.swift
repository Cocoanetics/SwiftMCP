import SwiftCross

extension MCPServerProxy {
    // MARK: - Streamable HTTP

    // Uses `URLSession.bytes(for:)` on every platform: native on Apple
    // (macOS 12 / iOS 15, the package floor) and via SwiftCross's shim on
    // Linux / Windows / Android.
    internal func sendStreamableRequest(
        _ message: JSONRPCMessage,
        sseConfig: MCPServerSseConfig
    ) async throws -> JSONRPCMessage {
        guard let requestID = message.id else {
            throw MCPServerProxyError.communicationError("Message must have an ID")
        }
        guard let endpointURL = endpointURL
            ?? (isStreamableMCPURL(sseConfig.url) ? sseConfig.url : nil) else {
            throw MCPServerProxyError.communicationError("Not connected to server")
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let requestBody = try encoder.encode(message)

        return try await streamableRequestResponse(
            endpointURL: endpointURL,
            sseConfig: sseConfig,
            requestID: requestID,
            requestBody: requestBody,
            lastEventID: nil,
            retryMilliseconds: 1000
        )
    }

    // swiftlint:disable:next function_parameter_count function_body_length cyclomatic_complexity
    internal func streamableRequestResponse(
        endpointURL: URL,
        sseConfig: MCPServerSseConfig,
        requestID: JSONRPCID,
        requestBody: Data?,
        lastEventID: String?,
        retryMilliseconds: Int
    ) async throws -> JSONRPCMessage {
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = .infinity
        sessionConfig.timeoutIntervalForResource = .infinity

        let session = URLSession(configuration: sessionConfig)
        var request = URLRequest(url: endpointURL)
        request.httpMethod = requestBody == nil ? "GET" : "POST"

        if let requestBody {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            configureSSEPOSTRequest(&request, sseConfig: sseConfig)
            request.httpBody = requestBody
        } else {
            configureSSEGETRequest(&request, sseConfig: sseConfig, lastEventID: lastEventID)
        }

        let (asyncBytes, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MCPServerProxyError.communicationError("Invalid HTTP response")
        }

        if let updatedSessionID = httpResponse.value(forHTTPHeaderField: "Mcp-Session-Id") {
            sessionID = updatedSessionID
        }

        let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        switch httpResponse.statusCode {
        case 200:
            if contentType.contains("application/json") {
                var data = Data()
                for try await byte in asyncBytes {
                    data.append(byte)
                }

                guard let responseMessage = try responseMessage(for: requestID, from: data) else {
                    throw MCPServerProxyError.communicationError(
                        "HTTP 200 did not include JSON-RPC response for request \(requestID.stringValue)"
                    )
                }
                return responseMessage
            }

            if contentType.contains("text/event-stream") {
                return try await readStreamableSSE(
                    asyncBytes: asyncBytes,
                    endpointURL: endpointURL,
                    sseConfig: sseConfig,
                    requestID: requestID,
                    lastEventID: lastEventID,
                    retryMilliseconds: retryMilliseconds
                )
            }

            throw MCPServerProxyError.communicationError(
                "Unsupported response content type: \(contentType)"
            )
        case 202:
            throw MCPServerProxyError.communicationError(
                "Unexpected HTTP 202 for request \(requestID.stringValue)"
            )
        default:
            var data = Data()
            for try await byte in asyncBytes {
                data.append(byte)
            }
            let responseBody = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let details = responseBody.isEmpty ? "" : ": \(responseBody)"
            throw MCPServerProxyError.communicationError(
                "HTTP error \(httpResponse.statusCode)\(details)"
            )
        }
    }

    // swiftlint:disable:next function_parameter_count function_body_length cyclomatic_complexity
    internal func readStreamableSSE(
        asyncBytes: URLSession.AsyncBytes,
        endpointURL: URL,
        sseConfig: MCPServerSseConfig,
        requestID: JSONRPCID,
        lastEventID: String?,
        retryMilliseconds: Int
    ) async throws -> JSONRPCMessage {
        var latestEventID = lastEventID
        var retryMilliseconds = retryMilliseconds

        do {
            for try await message in asyncBytes.lines.sseMessages() {
                if let id = message.id {
                    latestEventID = id
                }
                if let retry = message.retry {
                    retryMilliseconds = retry
                }

                if message.data.isEmpty {
                    continue
                }

                if let jsonData = message.data.data(using: .utf8),
                   let decoded = try? JSONDecoder().decode(JSONRPCMessage.self, from: jsonData),
                   decoded.id == requestID {
                    switch decoded {
                    case .response, .errorResponse:
                        return decoded
                    case .request, .notification:
                        break
                    }
                }

                await processIncomingMessage(event: message.event, data: message.data)
            }
        } catch is CancellationError {
            throw MCPServerProxyError.communicationError(
                "Request stream cancelled before response was received"
            )
        } catch {
            if let latestEventID {
                try await Task.sleep(nanoseconds: UInt64(retryMilliseconds) * 1_000_000)
                return try await streamableRequestResponse(
                    endpointURL: endpointURL,
                    sseConfig: sseConfig,
                    requestID: requestID,
                    requestBody: nil,
                    lastEventID: latestEventID,
                    retryMilliseconds: retryMilliseconds
                )
            }
            throw MCPServerProxyError.communicationError(error.localizedDescription)
        }

        if let latestEventID {
            try await Task.sleep(nanoseconds: UInt64(retryMilliseconds) * 1_000_000)
            return try await streamableRequestResponse(
                endpointURL: endpointURL,
                sseConfig: sseConfig,
                requestID: requestID,
                requestBody: nil,
                lastEventID: latestEventID,
                retryMilliseconds: retryMilliseconds
            )
        }

        throw MCPServerProxyError.communicationError(
            "SSE stream closed before response was received"
        )
    }
}
