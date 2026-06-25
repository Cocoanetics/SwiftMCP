#if Server && OpenAPI
import Foundation
import HTTPTypes

/// OpenAPI-related route handlers: AI plugin manifest, OpenAPI spec, and tool call endpoint.
extension HTTPSSETransport {

	/// Returns the OpenAPI routes if `serveOpenAPI` is enabled, otherwise an empty array.
	func openAPIRoutes() -> [HTTPRoute] {
		// OpenAPI introspects the server's tools, so it is only available in the
		// server-coupled mode.
		guard serveOpenAPI, server != nil else { return [] }

		let serverPath = "/\(coupledServer.serverName.asModelName)"

		return [
			// GET /.well-known/ai-plugin.json — AI plugin manifest
			HTTPRoute(.get, "/.well-known/ai-plugin.json", calling: HTTPSSETransport.handleAIPluginManifest),

			// GET /openapi.json — OpenAPI spec
			HTTPRoute(.get, "/openapi.json", calling: HTTPSSETransport.handleOpenAPISpec),

			// POST /{serverName}/:toolName — Tool call endpoint
			HTTPRoute(.post, "\(serverPath)/:toolName", calling: HTTPSSETransport.handleToolCallAsync)
		]
	}

	// MARK: - Handler Implementations

	/// Serve the AI plugin manifest JSON.
	func handleAIPluginManifest(request: HTTPRouteRequest<Data?>) async throws -> RouteResponse {

		let host: String
		let scheme: String

		if let forwardedHost = request.header("X-Forwarded-Host") {
			host = forwardedHost
		} else {
			host = self.host
		}

		if let forwardedProto = request.header("X-Forwarded-Proto") {
			scheme = forwardedProto
		} else {
			scheme = "http"
		}

		let description = coupledServer.serverDescription ?? "MCP Server providing tools for automation and integration"

		let manifest = AIPluginManifest(
			nameForHuman: coupledServer.serverName,
			nameForModel: coupledServer.serverName.asModelName,
			descriptionForHuman: description,
			descriptionForModel: description,
			auth: .none,
			api: .init(type: "openapi", url: "\(scheme)://\(host)/openapi.json")
		)

		let encoder = JSONEncoder()
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

		do {
			let jsonData = try encoder.encode(manifest)
			return RouteResponse(status: .ok, headerFields: [.contentType: "application/json"], body: jsonData)
		} catch {
			logger.error("Failed to encode AI plugin manifest: \(error)")
			return RouteResponse(status: .internalServerError)
		}
	}

	/// Generate and serve the OpenAPI spec.
	func handleOpenAPISpec(request: HTTPRouteRequest<Data?>) async throws -> RouteResponse {

		let host: String
		let scheme: String

		if let forwardedHost = request.header("X-Forwarded-Host") {
			host = forwardedHost
		} else {
			host = self.host
		}

		if let forwardedProto = request.header("X-Forwarded-Proto") {
			scheme = forwardedProto
		} else {
			scheme = "http"
		}

		let spec = await OpenAPISpec(server: coupledServer, scheme: scheme, host: host)

		let encoder = JSONEncoder()
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

		do {
			let jsonData = try encoder.encode(spec)
			return RouteResponse(status: .ok, headerFields: [.contentType: "application/json"], body: jsonData)
		} catch {
			logger.error("Failed to encode OpenAPI spec: \(error)")
			return RouteResponse(status: .internalServerError)
		}
	}

	/// Execute a tool via the OpenAPI endpoint.
	func handleToolCallAsync(request: HTTPRouteRequest<Data?>) async throws -> RouteResponse {
		let pathComponents = request.uri.split(separator: "/").map(String.init)

		guard pathComponents.count == 2,
			  let serverComponent = pathComponents.first,
			  let toolName = pathComponents.dropFirst().first,
			  serverComponent == coupledServer.serverName.asModelName
		else {
			return RouteResponse(status: .notFound)
		}

		let token = request.bearerToken
		let sessionID = UUID(uuidString: request.sessionID ?? "")

		if case .unauthorized(let message) = await authorize(token, sessionID: sessionID) {
			let err = JSONRPCMessage.errorResponse(id: nil, error: .init(code: -32000, message: "Unauthorized: \(message)"))
			let data = (try? JSONEncoder().encode(err)) ?? Data()
			return RouteResponse(status: .unauthorized, headerFields: [.contentType: "application/json"], body: data)
		}

		guard let body = request.body else {
			return RouteResponse(status: .badRequest)
		}

		do {
			let arguments = try MCPJSONCoding.makeDecoder().decode(JSONDictionary.self, from: body)
			let (result, metadata) = try await dispatchTool(toolName: toolName, arguments: arguments)
			let wrappedResult = try metadata?.wrapOutputIfNeeded(result) ?? result
			let responseToEncode = openAPIEncodable(for: wrappedResult)

			let encoder = MCPJSONCoding.makeValueEncoder()
			encoder.outputFormatting = [.prettyPrinted]
			let jsonData = try encoder.encode(responseToEncode)
			return RouteResponse(status: .ok, headerFields: [.contentType: "application/json"], body: jsonData)

		} catch {
			return openAPIErrorResponse(for: error)
		}
	}

	/// Dispatch a tool / resource / prompt by name and return its result along with metadata (if a tool).
	private func dispatchTool(toolName: String, arguments: JSONDictionary) async throws
		-> (Encodable & Sendable, MCPToolMetadata?) {
		if let toolProvider = coupledServer as? MCPToolProviding {
			let toolMetadata = await toolProvider.mcpToolMetadata
			if toolMetadata.contains(where: { $0.name == toolName }) {
				let metadata = toolMetadata.first(where: { $0.name == toolName })
				let result = try await toolProvider.callTool(toolName, arguments: arguments)
				return (result, metadata)
			}
		}
		if let resourceProvider = coupledServer as? MCPResourceProviding {
			let resourceMetadata = await resourceProvider.mcpResourceMetadata
			if resourceMetadata.contains(where: { $0.functionMetadata.name == toolName }) {
				let result = try await resourceProvider.callResourceAsFunction(toolName, arguments: arguments)
				return (result, nil)
			}
		}
		if let promptProvider = coupledServer as? MCPPromptProviding {
			let promptMetadata = await promptProvider.mcpPromptMetadata
			if promptMetadata.contains(where: { $0.name == toolName }) {
				let messages = try await promptProvider.callPrompt(toolName, arguments: arguments)
				return (messages, nil)
			}
		}
		throw MCPToolError.unknownTool(name: toolName)
	}

	/// Map a wrapped result to the Encodable representation used by OpenAPI responses.
	private func openAPIEncodable(for wrappedResult: Encodable) -> Encodable {
		if let encodableResult = openAPIScalarContent(for: wrappedResult) {
			return encodableResult
		}
		if let encodableArray = openAPIArrayContent(for: wrappedResult) {
			return encodableArray
		}
		if let resourceContent = wrappedResult as? MCPResourceContent {
			return MCPEmbeddedResource(resource: resourceContent)
		}
		if let resourceContentArray = wrappedResult as? [MCPResourceContent] {
			return resourceContentArray.map { MCPEmbeddedResource(resource: $0) }
		}
		return wrappedResult
	}

	/// Return the wrapped result re-cast to a known scalar content type, if it matches.
	private func openAPIScalarContent(for wrappedResult: Encodable) -> Encodable? {
		switch wrappedResult {
		case let toolResult as MCPText: return toolResult
		case let toolResult as MCPImage: return toolResult
		case let toolResult as MCPAudio: return toolResult
		case let toolResult as MCPResourceLink: return toolResult
		case let toolResult as MCPEmbeddedResource: return toolResult
		default: return nil
		}
	}

	/// Return the wrapped result re-cast to a known array content type, if it matches.
	private func openAPIArrayContent(for wrappedResult: Encodable) -> Encodable? {
		switch wrappedResult {
		case let toolResults as [MCPText]: return toolResults
		case let toolResults as [MCPImage]: return toolResults
		case let toolResults as [MCPAudio]: return toolResults
		case let toolResults as [MCPResourceLink]: return toolResults
		case let toolResults as [MCPEmbeddedResource]: return toolResults
		default: return nil
		}
	}

	/// Build a JSON error response with rich diagnostic information.
	private func openAPIErrorResponse(for error: Error) -> RouteResponse {
		let localizedDescription = error.localizedDescription
		let reflectedDescription = String(reflecting: error)
		let errorType = String(describing: type(of: error))
		let nsError = error as NSError

		var errorData: JSONDictionary = [
			"errorType": .string(errorType),
			"debugDescription": .string(reflectedDescription),
			"localizedDescription": .string(localizedDescription),
			"nsErrorDomain": .string(nsError.domain),
			"nsErrorCode": .integer(nsError.code)
		]

		if let localizedError = error as? LocalizedError {
			if let failureReason = localizedError.failureReason {
				errorData["failureReason"] = .string(failureReason)
			}
			if let recoverySuggestion = localizedError.recoverySuggestion {
				errorData["recoverySuggestion"] = .string(recoverySuggestion)
			}
		}

		let err = JSONRPCMessage.errorResponse(
			id: nil,
			error: .init(code: -32000, message: localizedDescription, data: .object(errorData))
		)

		let data = (try? JSONEncoder().encode(err)) ?? Data()

		var status: HTTPResponse.Status = .badRequest
		if let mcpError = error as? MCPToolError, case .unknownTool = mcpError {
			status = .notFound
		}

		return RouteResponse(status: status, headerFields: [.contentType: "application/json"], body: data)
	}
}
#endif
