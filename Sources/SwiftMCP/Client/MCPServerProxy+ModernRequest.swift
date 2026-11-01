#if Client
import Foundation

/// The modern (`2026-07-28`) request path: per-request `_meta` and the redundant
/// HTTP headers. Every request flows through ``send(_:)``, which applies this
/// once ``negotiatedEra`` is ``MCPClientEra/modern``; legacy connections are
/// untouched.
extension MCPServerProxy {
    /// `message` with the reserved `_meta` keys injected: user `meta` and any
    /// `progressToken` first, then the protocol version, client identity and
    /// capabilities (and the log level when configured), which always win.
    internal func injectingModernMeta(into message: JSONRPCMessage) -> JSONRPCMessage {
        guard let modernProtocolVersion else {
            return message
        }
        switch message {
        case .request(let request) where request.method != "initialize":
            return .request(
                id: request.id,
                method: request.method,
                params: modernParams(request.params, version: modernProtocolVersion)
            )
        case .notification(let notification) where notification.method != "notifications/initialized":
            return .notification(
                method: notification.method,
                params: modernParams(notification.params, version: modernProtocolVersion)
            )
        default:
            return message
        }
    }

    private func modernParams(_ params: JSONValue?, version: String) -> JSONValue {
        var dictionary = params?.dictionaryValue ?? [:]
        var requestMeta = meta
        requestMeta.merge(dictionary["_meta"]?.dictionaryValue ?? [:]) { _, new in new }
        requestMeta[MCPMetaKey.protocolVersion] = .string(version)
        requestMeta[MCPMetaKey.clientInfo] = .object([
            "name": .string(clientIdentity.name),
            "version": .string(clientIdentity.version)
        ])
        requestMeta[MCPMetaKey.clientCapabilities] = .object(modernClientCapabilities())
        if let requestLogLevel {
            requestMeta[MCPMetaKey.logLevel] = .string(requestLogLevel.rawValue)
        }
        dictionary["_meta"] = .object(requestMeta)
        return .object(dictionary)
    }

    /// The capabilities declared on every modern request: the notification
    /// capabilities plus whatever the input handler can answer (MRTR).
    internal func modernClientCapabilities() -> JSONDictionary {
        var capabilities = buildClientCapabilities()
        for method in inputHandler?.supportedMethods ?? [] {
            switch method {
            case "elicitation/create": capabilities["elicitation"] = .object([:])
            case "sampling/createMessage": capabilities["sampling"] = .object([:])
            case "roots/list": capabilities["roots"] = .object(capabilities["roots"]?.dictionaryValue ?? [:])
            default: break
            }
        }
        return capabilities
    }

    /// The required modern headers for an already-modernized `message`:
    /// `Mcp-Method`, `Mcp-Name` (`tools/call`, `prompts/get`, `resources/read`)
    /// and a `Mcp-Param-{name}` per mirrored tool argument. (`MCP-Protocol-Version`
    /// is applied with the other transport headers.)
    internal func modernRequestHeaders(for message: JSONRPCMessage) async throws -> [String: String] {
        let method: String
        let params: JSONValue?
        switch message {
        case .request(let request):
            (method, params) = (request.method, request.params)
        case .notification(let notification):
            (method, params) = (notification.method, notification.params)
        default:
            return [:]
        }

        var headers = ["Mcp-Method": method]
        switch method {
        case "tools/call", "prompts/get":
            headers["Mcp-Name"] = params?["name"]?.stringValue
        case "resources/read":
            headers["Mcp-Name"] = params?["uri"]?.stringValue
        default:
            break
        }

        if method == "tools/call", let name = params?["name"]?.stringValue,
           let arguments = params?["arguments"]?.dictionaryValue, !arguments.isEmpty {
            let mirrored = try await mirroredParameters(forTool: name)
            for (parameter, suffix) in mirrored {
                if let value = arguments[parameter], let encoded = MCPParamHeader.encode(value) {
                    headers["Mcp-Param-\(suffix)"] = encoded
                }
            }
        }
        return headers
    }

    /// `parameter name → header suffix` for `tool`, loading the tools list once
    /// when it is not known yet.
    private func mirroredParameters(forTool tool: String) async throws -> [String: String] {
        if headerParameters == nil {
            let result = try await requestResult(method: "tools/list")
            recordHeaderParameters(from: result)
        }
        return headerParameters?[tool] ?? [:]
    }

    /// Records the `x-mcp-header` annotations of a raw `tools/list` result. The
    /// annotation is `true` (header named after the parameter) or a string (the
    /// header name suffix).
    internal func recordHeaderParameters(from toolsListResult: JSONDictionary) {
        var parameters: [String: [String: String]] = [:]
        for tool in toolsListResult["tools"]?.arrayValue ?? [] {
            guard let name = tool["name"]?.stringValue,
                  let properties = tool["inputSchema"]?["properties"]?.dictionaryValue else {
                continue
            }
            for (parameter, schema) in properties {
                if schema["x-mcp-header"]?.boolValue == true {
                    parameters[name, default: [:]][parameter] = parameter
                } else if let suffix = schema["x-mcp-header"]?.stringValue {
                    parameters[name, default: [:]][parameter] = suffix
                }
            }
        }
        headerParameters = parameters
    }

    /// Maps the modern-only protocol errors to typed ones; other codes pass through.
    internal func typedModernError(_ error: JSONRPCError) -> MCPServerProxyError? {
        guard negotiatedEra == .modern else {
            return nil
        }
        switch error.code {
        case -32004:
            let supported = error.data?["supported"]?.arrayValue?.compactMap { $0.stringValue } ?? []
            return .unsupportedProtocolVersion(supported: supported)
        case -32001:
            return .headerMismatch(error.message)
        default:
            return nil
        }
    }
}
#endif
