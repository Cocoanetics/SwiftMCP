import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif
import Logging

extension MCPServerProxy {
    internal func logIncomingLogMessage(_ message: LogMessage) {
        var parts: [String] = []
        parts.append("level \(message.level.rawValue)")
        if let loggerName = message.logger, !loggerName.isEmpty {
            parts.append("logger \(loggerName)")
        }
        let dataDescription = String(describing: message.data)
        if !dataDescription.isEmpty {
            parts.append("data \(dataDescription)")
        }

        let level = loggerLevel(for: message.level)
        if parts.isEmpty {
            logger.log(level: level, "[MCP] Log notification received.")
        } else {
            logger.log(level: level, "[MCP] Log: \(parts.joined(separator: " | "))")
        }
    }

    internal func logIncomingLogMessage(_ notification: JSONRPCMessage.JSONRPCNotificationData) {
        guard let params = notification.params else {
            logger.info("[MCP] Log notification received.")
            return
        }

        let levelValue = params["level"]?.stringValue
        let level = levelValue.flatMap(LogLevel.init(string:)) ?? .info
        let loggerName = params["logger"]?.stringValue
        let dataValue = params["data"] ?? .string("")
        let message = LogMessage(level: level, logger: loggerName, data: dataValue)
        logIncomingLogMessage(message)
    }

    internal func loggerLevel(for level: LogLevel) -> Logger.Level {
        switch level {
        case .debug:
            return .debug
        case .info:
            return .info
        case .notice:
            return .notice
        case .warning:
            return .warning
        case .error:
            return .error
        case .critical, .alert, .emergency:
            return .critical
        }
    }

    internal func numericValue(_ value: JSONValue?) -> Double? {
        value?.doubleValue
    }

    internal func extractTextPayload(from contentArray: JSONArray) -> String? {
        guard contentArray.count == 1 else {
            return nil
        }
        for content in contentArray {
            guard let contentDict = contentDictionary(from: content),
                  let type = stringValue(contentDict["type"]),
                  type == "text",
                  let text = stringValue(contentDict["text"]) else {
                continue
            }
            return text
        }
        return nil
    }

    internal func encodeContentPayload(from contentArray: JSONArray) -> String? {
        let normalized = contentArray.compactMap {
            contentDictionary(from: $0).map(JSONValue.object)
        }
        if normalized.isEmpty {
            return "[]"
        }
        let payload: JSONValue = normalized.count == 1 ? normalized[0] : .array(normalized)
        let encoder = MCPJSONCoding.makeWireEncoder()
        guard let data = try? encoder.encode(payload),
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }

    internal func contentDictionary(from value: JSONValue) -> JSONDictionary? {
        value.dictionaryValue
    }

    internal func stringValue(_ value: JSONValue?) -> String? {
        value?.stringValue
    }

    internal func requestResult(
        method: String,
        params: JSONDictionary? = nil
    ) async throws -> JSONDictionary {
        let requestId = nextRequestID()
        var requestParams = params ?? [:]

        if !meta.isEmpty {
            var requestMeta = meta
            if let existingMeta = requestParams["_meta"]?.dictionaryValue {
                requestMeta.merge(existingMeta) { _, new in new }
            }
            requestParams["_meta"] = .object(requestMeta)
        }

        let request = JSONRPCMessage.request(
            id: requestId,
            method: method,
            params: requestParams.isEmpty ? nil : requestParams
        )
        let response = try await send(request)

        switch response {
        case .response(let responseData):
            guard let result = responseData.result else {
                throw MCPServerProxyError.communicationError("Invalid response type for \(method)")
            }
            if result["isError"]?.boolValue == true {
                throw MCPServerProxyError.communicationError(
                    errorMessage(from: result) ?? "Request failed for \(method)"
                )
            }
            return result
        case .errorResponse(let errorResponse):
            throw MCPServerProxyError.communicationError(errorResponse.error.message)
        default:
            throw MCPServerProxyError.communicationError("Invalid response type for \(method)")
        }
    }

    internal func requestResult<T: Decodable>(
        method: String,
        params: JSONDictionary? = nil,
        as type: T.Type = T.self
    ) async throws -> T {
        let result = try await requestResult(method: method, params: params)
        return try result.decoded(type)
    }

    internal static func decodeJSONPayload<T: Decodable, Payload: Encodable>(
        _ payload: Payload,
        as type: T.Type = T.self
    ) throws -> T {
        let encoder = MCPJSONCoding.makeWireEncoder()
        let data = try encoder.encode(payload)

        let decoder = MCPJSONCoding.makeDecoder()
        return try decoder.decode(type, from: data)
    }

    internal func errorMessage(from result: JSONDictionary) -> String? {
        if let message = stringValue(result["message"]) {
            return message
        }
        if let contentArray = result["content"]?.arrayValue {
            return extractTextPayload(from: contentArray)
        }
        return nil
    }

    internal func extractServerDescription(from result: JSONDictionary) -> String? {
        result["serverInfo"]?.dictionaryValue?["description"]?.stringValue
    }

    internal func progressPercentText(progressValue: Double, totalValue: Double?) -> String? {
        if let totalValue, totalValue > 0 {
            return formatPercent((progressValue / totalValue) * 100)
        }
        if progressValue >= 0, progressValue <= 1 {
            return formatPercent(progressValue * 100)
        }
        return nil
    }

    internal func formatPercent(_ percent: Double) -> String {
        let rounded = Int(percent.rounded())
        return "\(rounded)%"
    }

    internal func responseMessage(
        for requestID: JSONRPCID,
        from data: Data
    ) throws -> JSONRPCMessage? {
        guard !data.isEmpty else {
            return nil
        }

        let messages = try JSONRPCMessage.decodeMessages(from: data)
        return messages.first { message in
            guard message.id == requestID else {
                return false
            }
            switch message {
            case .response, .errorResponse:
                return true
            case .request, .notification:
                return false
            }
        }
    }
}
