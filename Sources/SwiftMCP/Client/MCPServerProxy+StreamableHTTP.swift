import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

extension MCPServerProxy {
    // MARK: - Streamable HTTP (Apple platforms)

    #if !canImport(FoundationNetworking)
        @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, macCatalyst 15.0, *)
        internal func sendStreamableRequestApple(
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

            return try await streamableRequestResponseApple(
                endpointURL: endpointURL,
                sseConfig: sseConfig,
                requestID: requestID,
                requestBody: requestBody,
                lastEventID: nil,
                retryMilliseconds: 1000
            )
        }

        @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, macCatalyst 15.0, *)
        // swiftlint:disable:next function_parameter_count function_body_length cyclomatic_complexity
        internal func streamableRequestResponseApple(
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
                    return try await readStreamableSSEApple(
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

        @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, macCatalyst 15.0, *)
        // swiftlint:disable:next function_parameter_count function_body_length cyclomatic_complexity
        internal func readStreamableSSEApple(
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
                    return try await streamableRequestResponseApple(
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
                return try await streamableRequestResponseApple(
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
    #endif

    // MARK: - Streamable HTTP (Linux, Android, Windows)

    #if canImport(FoundationNetworking)
        internal func sendStreamableRequestLinux(
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

            return try await streamableRequestResponseLinux(
                endpointURL: endpointURL,
                sseConfig: sseConfig,
                requestID: requestID,
                requestBody: requestBody,
                lastEventID: nil,
                retryMilliseconds: 1000
            )
        }

        // swiftlint:disable:next function_parameter_count function_body_length cyclomatic_complexity
        internal func streamableRequestResponseLinux(
            endpointURL: URL,
            sseConfig: MCPServerSseConfig,
            requestID: JSONRPCID,
            requestBody: Data?,
            lastEventID: String?,
            retryMilliseconds: Int
        ) async throws -> JSONRPCMessage {
            let delegate = SSEStreamingDelegate { _ in }
            let session = URLSession(
                configuration: .ephemeral,
                delegate: delegate,
                delegateQueue: nil
            )

            var request = URLRequest(url: endpointURL)
            request.httpMethod = requestBody == nil ? "GET" : "POST"

            if let requestBody {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = requestBody
                configureSSEPOSTRequest(&request, sseConfig: sseConfig)
            } else {
                configureSSEGETRequest(&request, sseConfig: sseConfig, lastEventID: lastEventID)
            }

            let task = session.dataTask(with: request)
            task.resume()

            let response = await delegate.waitForResponse()
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
                    var bodyLines: [String] = []
                    for await line in delegate.lines {
                        bodyLines.append(line)
                    }

                    let body = bodyLines.joined(separator: "\n")
                    guard let responseMessage = try responseMessage(
                        for: requestID,
                        from: Data(body.utf8)
                    ) else {
                        throw MCPServerProxyError.communicationError(
                            "HTTP 200 did not include JSON-RPC response for request \(requestID.stringValue)"
                        )
                    }
                    return responseMessage
                }

                if contentType.contains("text/event-stream") {
                    return try await readStreamableSSELinux(
                        delegate: delegate,
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
                var bodyLines: [String] = []
                for await line in delegate.lines {
                    bodyLines.append(line)
                }

                let responseBody = bodyLines.joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let details = responseBody.isEmpty ? "" : ": \(responseBody)"
                throw MCPServerProxyError.communicationError(
                    "HTTP error \(httpResponse.statusCode)\(details)"
                )
            }
        }

        // swiftlint:disable:next function_parameter_count
        internal func readStreamableSSELinux(
            delegate: SSEStreamingDelegate,
            endpointURL: URL,
            sseConfig: MCPServerSseConfig,
            requestID: JSONRPCID,
            lastEventID: String?,
            retryMilliseconds: Int
        ) async throws -> JSONRPCMessage {
            var latestEventID = lastEventID
            var retryMilliseconds = retryMilliseconds

            for try await message in delegate.lines.sseMessages() {
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

            if let latestEventID {
                try await Task.sleep(nanoseconds: UInt64(retryMilliseconds) * 1_000_000)
                return try await streamableRequestResponseLinux(
                    endpointURL: endpointURL,
                    sseConfig: sseConfig,
                    requestID: requestID,
                    requestBody: nil,
                    lastEventID: latestEventID,
                    retryMilliseconds: retryMilliseconds
                )
            }

            if let completionError = delegate.completionError {
                throw MCPServerProxyError.communicationError(completionError.localizedDescription)
            }

            throw MCPServerProxyError.communicationError(
                "SSE stream closed before response was received"
            )
        }
    #endif
}
