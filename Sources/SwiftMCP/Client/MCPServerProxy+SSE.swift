import SwiftCross

extension MCPServerProxy {
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

    // MARK: - SSE Connection (Apple platforms)

    #if !os(Linux)
        @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, macCatalyst 15.0, *)
        internal func connectSSEApple(
            sseConfig: MCPServerSseConfig,
            clientName: String,
            clientVersion: String
        ) async throws {
            let isStreamableMCP = isStreamableMCPURL(sseConfig.url)
            if isStreamableMCP {
                endpointURL = sseConfig.url
                try await initialize(clientName: clientName, clientVersion: clientVersion)
                startStreamableGeneralSSEApple(sseConfig: sseConfig)
                return
            }

            let sessionConfig = URLSessionConfiguration.default
            sessionConfig.timeoutIntervalForRequest = .infinity
            sessionConfig.timeoutIntervalForResource = .infinity

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
    #endif

    // MARK: - SSE Connection (Linux)

    #if os(Linux)
        internal func connectSSELinux(
            sseConfig: MCPServerSseConfig,
            clientName: String,
            clientVersion: String
        ) async throws {
            let isStreamableMCP = isStreamableMCPURL(sseConfig.url)
            if isStreamableMCP {
                endpointURL = sseConfig.url
                try await initialize(clientName: clientName, clientVersion: clientVersion)
                startStreamableGeneralSSELinux(sseConfig: sseConfig)
                return
            }

            let sessionConfig = URLSessionConfiguration.default

            var request = URLRequest(url: sseConfig.url)
            request.httpMethod = "GET"
            configureSSEGETRequest(&request, sseConfig: sseConfig)

            // Use a streaming delegate since URLSession.bytes is unavailable on Linux
            let proxy = self
            let delegate = SSEStreamingDelegate { response in
                Task {
                    await proxy.handleSSEResponse(
                        response,
                        sseConfig: sseConfig,
                        isStreamableMCP: isStreamableMCP
                    )
                }
            }

            let session = URLSession(
                configuration: sessionConfig,
                delegate: delegate,
                delegateQueue: nil
            )
            let task = session.dataTask(with: request)
            task.resume()

            streamTask = Task {
                do {
                    for try await message in delegate.lines.sseMessages() {
                        await self.processIncomingMessage(event: message.event, data: message.data)
                    }
                    self.handleStreamTermination(
                        MCPServerProxyError.communicationError(
                            "SSE stream closed by server before response was received"
                        )
                    )
                } catch is CancellationError {
                    task.cancel()
                } catch {
                    self.logger.error("[MCP DEBUG] SSE stream error: \(error)")
                    self.handleStreamTermination(error)
                }
            }

            try await waitForEndpointIfNeeded(isStreamableMCP: isStreamableMCP)
            try await initialize(clientName: clientName, clientVersion: clientVersion)
        }
    #endif

    // MARK: - Streamable general SSE (Apple)

    #if !os(Linux)
        @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, macCatalyst 15.0, *)
        // swiftlint:disable:next function_body_length
        internal func startStreamableGeneralSSEApple(sseConfig: MCPServerSseConfig) {
            streamTask = Task {
                var lastEventID: String?
                var retryMilliseconds = 1000

                while !self.isDisconnecting {
                    do {
                        let sessionConfig = URLSessionConfiguration.default
                        sessionConfig.timeoutIntervalForRequest = .infinity
                        sessionConfig.timeoutIntervalForResource = .infinity

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
    #endif

    // MARK: - Streamable general SSE (Linux)

    #if os(Linux)
        // swiftlint:disable:next function_body_length
        internal func startStreamableGeneralSSELinux(sseConfig: MCPServerSseConfig) {
            streamTask = Task {
                var lastEventID: String?
                var retryMilliseconds = 1000

                while !self.isDisconnecting {
                    let sessionConfig = URLSessionConfiguration.default
                    let proxy = self
                    let delegate = SSEStreamingDelegate { response in
                        Task {
                            await proxy.handleSSEResponse(
                                response,
                                sseConfig: sseConfig,
                                isStreamableMCP: true
                            )
                        }
                    }

                    var request = URLRequest(url: sseConfig.url)
                    request.httpMethod = "GET"
                    self.configureSSEGETRequest(
                        &request,
                        sseConfig: sseConfig,
                        lastEventID: lastEventID
                    )

                    let session = URLSession(
                        configuration: sessionConfig,
                        delegate: delegate,
                        delegateQueue: nil
                    )
                    let task = session.dataTask(with: request)
                    task.resume()

                    do {
                        for try await message in delegate.lines.sseMessages() {
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
                        task.cancel()
                        return
                    } catch {
                        if self.isDisconnecting {
                            task.cancel()
                            return
                        }
                        self.logger.error("[MCP DEBUG] Streamable general SSE stream error: \(error)")
                    }

                    if self.isDisconnecting {
                        task.cancel()
                        return
                    }

                    do {
                        try await Task.sleep(nanoseconds: UInt64(retryMilliseconds) * 1_000_000)
                    } catch {
                        task.cancel()
                        return
                    }
                }
            }
        }
    #endif

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
