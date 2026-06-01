import SwiftCross

extension MCPServerProxy {
    /// Effectively-unbounded timeout for long-lived SSE / streamable
    /// connections, expressed as a large *finite* value rather than
    /// `.infinity`: swift-corelibs-foundation traps (SIGILL) when converting
    /// an infinite timeout while configuring libcurl (`configureEasyHandle`)
    /// on Linux. Apple's Foundation tolerates `.infinity`, but a large finite
    /// value behaves identically there and is portable. `2^53` is effectively
    /// infinite (~285M years) yet keeps corelibs' `Int(seconds) * 1000` within
    /// `Int`.
    static let streamTimeout: TimeInterval = TimeInterval(1 << 53)

    // MARK: - URL helpers

    internal func isStreamableMCPURL(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false
        }
        return components.path.hasPrefix("/mcp")
    }

    internal func applyConfiguredSSEHeaders(
        _ request: inout URLRequest,
        sseConfig: MCPServerSseConfig
    ) {
        for (key, value) in sseConfig.headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        // Allow token in metadata to override auth header from config.
        if let accessToken = meta["accessToken"]?.stringValue {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
    }

    internal func applyStreamableProtocolHeaders(_ request: inout URLRequest) {
        request.setValue(
            HTTPSSETransport.latestProtocolVersion,
            forHTTPHeaderField: "MCP-Protocol-Version"
        )
        if let sessionID {
            request.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id")
        }
    }

    internal func configureSSEPOSTRequest(
        _ request: inout URLRequest,
        sseConfig: MCPServerSseConfig
    ) {
        applyConfiguredSSEHeaders(&request, sseConfig: sseConfig)
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")

        if isStreamableMCPURL(sseConfig.url) {
            applyStreamableProtocolHeaders(&request)
        } else if let sessionID {
            request.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id")
        }
    }

    internal func configureSSEGETRequest(
        _ request: inout URLRequest,
        sseConfig: MCPServerSseConfig,
        lastEventID: String? = nil
    ) {
        applyConfiguredSSEHeaders(&request, sseConfig: sseConfig)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        if isStreamableMCPURL(sseConfig.url) {
            applyStreamableProtocolHeaders(&request)
            if let lastEventID {
                request.setValue(lastEventID, forHTTPHeaderField: "Last-Event-ID")
            }
        }
    }

    // MARK: - SSE Connection

    // Uses `URLSession.bytes(for:)` on every platform: native on Apple
    // (macOS 12 / iOS 15, the package floor) and via SwiftCross's shim on
    // Linux / Windows / Android.
    internal func connectSSEStream(
        sseConfig: MCPServerSseConfig,
        clientName: String,
        clientVersion: String
    ) async throws {
        let isStreamableMCP = isStreamableMCPURL(sseConfig.url)
        if isStreamableMCP {
            endpointURL = sseConfig.url
            try await initialize(clientName: clientName, clientVersion: clientVersion)
            startStreamableGeneralSSE(sseConfig: sseConfig)
            return
        }

        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = Self.streamTimeout
        sessionConfig.timeoutIntervalForResource = Self.streamTimeout

        let session = URLSession(configuration: sessionConfig)
        var request = URLRequest(url: sseConfig.url)
        request.httpMethod = "GET"
        configureSSEGETRequest(&request, sseConfig: sseConfig)

        streamTask = Task {
            do {
                let (asyncBytes, response) = try await session.bytes(for: request)
                self.handleSSEResponse(
                    response,
                    sseConfig: sseConfig,
                    isStreamableMCP: isStreamableMCP
                )

                for try await message in asyncBytes.lines.sseMessages() {
                    await self.processIncomingMessage(event: message.event, data: message.data)
                }
                self.handleStreamTermination(
                    MCPServerProxyError.communicationError(
                        "SSE stream closed by server before response was received"
                    )
                )
            } catch is CancellationError {
                // Pending requests are cancelled in disconnect().
            } catch {
                self.logger.error("[MCP DEBUG] SSE stream error: \(error)")
                self.handleStreamTermination(error)
            }
        }

        try await waitForEndpointIfNeeded(isStreamableMCP: isStreamableMCP)
        try await initialize(clientName: clientName, clientVersion: clientVersion)
    }

    // MARK: - Streamable general SSE

    // swiftlint:disable:next function_body_length
    internal func startStreamableGeneralSSE(sseConfig: MCPServerSseConfig) {
        streamTask = Task {
            var lastEventID: String?
            var retryMilliseconds = 1000

            while !self.isDisconnecting {
                do {
                    let sessionConfig = URLSessionConfiguration.default
                    sessionConfig.timeoutIntervalForRequest = Self.streamTimeout
                    sessionConfig.timeoutIntervalForResource = Self.streamTimeout

                    let session = URLSession(configuration: sessionConfig)
                    var request = URLRequest(url: sseConfig.url)
                    request.httpMethod = "GET"
                    self.configureSSEGETRequest(
                        &request,
                        sseConfig: sseConfig,
                        lastEventID: lastEventID
                    )

                    let (asyncBytes, response) = try await session.bytes(for: request)
                    self.handleSSEResponse(
                        response,
                        sseConfig: sseConfig,
                        isStreamableMCP: true
                    )

                    for try await message in asyncBytes.lines.sseMessages() {
                        if let id = message.id {
                            lastEventID = id
                        }
                        if let retry = message.retry {
                            retryMilliseconds = retry
                        }
                        await self.processIncomingMessage(
                            event: message.event,
                            data: message.data
                        )
                    }
                } catch is CancellationError {
                    return
                } catch {
                    if self.isDisconnecting {
                        return
                    }
                    self.logger.error("[MCP DEBUG] Streamable general SSE stream error: \(error)")
                }

                if self.isDisconnecting {
                    return
                }

                do {
                    try await Task.sleep(nanoseconds: UInt64(retryMilliseconds) * 1_000_000)
                } catch {
                    return
                }
            }
        }
    }

    // MARK: - Shared SSE Helpers

    internal func handleSSEResponse(
        _ response: URLResponse,
        sseConfig: MCPServerSseConfig,
        isStreamableMCP: Bool
    ) {
        if let httpResponse = response as? HTTPURLResponse {
            sessionID = httpResponse.value(forHTTPHeaderField: "Mcp-Session-Id")
            if isStreamableMCP {
                endpointURL = sseConfig.url
            } else if let sessionID,
                      let endpoint = messageEndpointURL(
                        baseURL: sseConfig.url,
                        sessionId: sessionID
                      ) {
                endpointURL = endpoint
            }
        }
    }

    internal func waitForEndpointIfNeeded(isStreamableMCP: Bool) async throws {
        if !isStreamableMCP && endpointURL == nil {
            _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
                self.endpointContinuation = continuation

                Task {
                    try await Task.sleep(nanoseconds: 10_000_000_000)
                    if let cont = self.endpointContinuation {
                        self.endpointContinuation = nil
                        cont.resume(throwing: MCPServerProxyError.communicationError(
                            "Timeout waiting for endpoint URL"
                        ))
                    }
                }
            }
        }
    }

    internal func messageEndpointURL(baseURL: URL, sessionId: String) -> URL? {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.path = "/messages/\(sessionId)"
        return components.url
    }
}
