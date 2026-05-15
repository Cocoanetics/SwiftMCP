import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

extension MCPServerProxy {
    internal func processIncomingMessage(event: String = "", data: String) async {
        if data.isEmpty {
            return
        }

        if event == "endpoint" {
            if case .sse(let sseConfig) = config, isStreamableMCPURL(sseConfig.url) {
                // Ignore legacy endpoint events for streamable /mcp mode.
                return
            }
            if let url = URL(string: data) {
                endpointURL = url
                if let continuation = endpointContinuation {
                    endpointContinuation = nil
                    continuation.resume(returning: url)
                }
                return
            }
        }

        guard let jsonData = data.data(using: .utf8) else { return }
        logger.trace("[MCP DEBUG] Received JSON-RPC message: \(data)")
        let decoder = JSONDecoder()
        if let message = try? decoder.decode(JSONRPCMessage.self, from: jsonData) {
            await dispatchDecodedMessage(message)
        } else {
            logger.error("[MCP DEBUG] Failed to decode JSON-RPC message")
        }
    }

    private func dispatchDecodedMessage(_ message: JSONRPCMessage) async {
        switch message {
        case .request(let requestData):
            if requestData.method == "ping" {
                logger.info("[MCP] Ping request received; sending response.")
                await handlePingRequest(requestData)
            } else {
                logger.debug("[MCP DEBUG] Ignoring client request: \(requestData.method)")
            }
        case .notification(let notification):
            await handleNotification(notification)
        case .response, .errorResponse:
            if let id = message.id, let waitingContinuation = responseTasks[id] {
                responseTasks.removeValue(forKey: id)
                waitingContinuation.resume(returning: message)
            } else {
                let idString = message.id?.stringValue ?? "nil"
                logger.error("[MCP DEBUG] No waiting continuation found for ID \(idString)")
            }
        }
    }

    internal func handleNotification(_ notification: JSONRPCMessage.JSONRPCNotificationData) async {
        if let handler = notificationHandlers[notification.method] {
            do {
                try await handler.handle(self, notification)
                return
            } catch {
                let method = notification.method
                let payloadDescription = handler.payloadTypeDescription
                let errorDescription = String(describing: error)
                logger.error(
                    "[MCP] Failed to handle \(method) as \(payloadDescription): \(errorDescription)"
                )
            }
        }

        handleUnhandledNotification(notification)
    }

    private func handlePingRequest(_ request: JSONRPCMessage.JSONRPCRequestData) async {
        guard let endpointURL = endpointURL else { return }
        guard case .sse(let sseConfig) = config else { return }
        let response = JSONRPCMessage.response(id: request.id, result: [:])
        let sessionConfig = URLSessionConfiguration.default
        let session = URLSession(configuration: sessionConfig)
        var urlRequest = URLRequest(url: endpointURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        configureSSEPOSTRequest(&urlRequest, sseConfig: sseConfig)
        let encoder = JSONEncoder()
        let data = try? encoder.encode(response)
        urlRequest.httpBody = data
        do {
            let (_, response) = try await session.data(for: urlRequest)
            if let httpResponse = response as? HTTPURLResponse,
               ![200, 202].contains(httpResponse.statusCode) {
                return
            }
        } catch {
            return
        }
    }

    private func handleUnhandledNotification(
        _ notification: JSONRPCMessage.JSONRPCNotificationData
    ) {
        switch notification.method {
        case NotificationMethod.progress:
            logProgressNotification(notification)
        case NotificationMethod.log:
            logIncomingLogMessage(notification)
        default:
            logger.trace("[MCP DEBUG] Received notification: \(notification.method)")
        }
    }

    private func logProgressNotification(
        _ notification: JSONRPCMessage.JSONRPCNotificationData
    ) {
        guard let params = notification.params else {
            logger.info("[MCP] Progress notification received.")
            return
        }
        let tokenValue = params["progressToken"]
        let progressValue = numericValue(params["progress"])
        let totalValue = numericValue(params["total"])
        let messageValue = params["message"]?.stringValue

        let parts = buildProgressParts(
            messageValue: messageValue,
            progressValue: progressValue,
            totalValue: totalValue,
            tokenValue: tokenValue
        )

        if parts.isEmpty {
            logger.info("[MCP] Progress notification received.")
        } else {
            logger.info("[MCP] Progress: \(parts.joined(separator: " | "))")
        }
    }

    private func buildProgressParts(
        messageValue: String?,
        progressValue: Double?,
        totalValue: Double?,
        tokenValue: JSONValue?
    ) -> [String] {
        var parts: [String] = []
        if let messageValue, !messageValue.isEmpty {
            parts.append(messageValue)
        }
        if let progressValue {
            if let percentText = progressPercentText(
                progressValue: progressValue,
                totalValue: totalValue
            ) {
                parts.append("progress \(percentText)")
            } else if let totalValue {
                parts.append("progress \(progressValue)/\(totalValue)")
            } else {
                parts.append("progress \(progressValue)")
            }
        }
        if let tokenValue {
            parts.append("token \(tokenValue)")
        }
        return parts
    }

    internal func handleLogNotification(
        _ notification: JSONRPCMessage.JSONRPCNotificationData
    ) async {
        await handleNotification(notification)
    }
}
