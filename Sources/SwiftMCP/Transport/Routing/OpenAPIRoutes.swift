import Foundation


/// OpenAPI-related route handlers: AI plugin manifest, OpenAPI spec, and tool call endpoint.
extension HTTPSSETransport {

	/// Returns the OpenAPI routes if `serveOpenAPI` is enabled, otherwise an empty array.
	func openAPIRoutes() -> [HTTPRoute] {
		guard serveOpenAPI else { return [] }

		let serverPath = "/\(server.serverName.asModelName)"

		return [
			// GET /.well-known/ai-plugin.json — AI plugin manifest
			HTTPRoute(.GET, "/.well-known/ai-plugin.json", calling: HTTPSSETransport.handleAIPluginManifest),

			// GET /openapi.json — OpenAPI spec
			HTTPRoute(.GET, "/openapi.json", calling: HTTPSSETransport.handleOpenAPISpec),

			// POST /{serverName}/:toolName — Tool call endpoint
			HTTPRoute(.POST, "\(serverPath)/:toolName", calling: HTTPSSETransport.handleToolCallAsync),
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

		let description = server.serverDescription ?? "MCP Server providing tools for automation and integration"

		let manifest = AIPluginManifest(
			nameForHuman: server.serverName,
			nameForModel: server.serverName.asModelName,
			descriptionForHuman: description,
			descriptionForModel: description,
			auth: .none,
			api: .init(type: "openapi", url: "\(scheme)://\(host)/openapi.json")
		)

		let encoder = JSONEncoder()
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

		do {
			let jsonData = try encoder.encode(manifest)
			return RouteResponse(status: .ok, headers: [("Content-Type", "application/json")], body: jsonData)
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

		let spec = OpenAPISpec(server: server, scheme: scheme, host: host)

		let encoder = JSONEncoder()
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

		do {
			let jsonData = try encoder.encode(spec)
			return RouteResponse(status: .ok, headers: [("Content-Type", "application/json")], body: jsonData)
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
			  serverComponent == server.serverName.asModelName
		else {
			return RouteResponse(status: .notFound)
		}

		let token = request.bearerToken
		let sessionID = UUID(uuidString: request.sessionID ?? "")

		if case .unauthorized(let message) = await authorize(token, sessionID: sessionID) {
			let err = JSONRPCMessage.errorResponse(id: nil, error: .init(code: -32000, message: "Unauthorized: \(message)"))
			let data = try! JSONEncoder().encode(err)
			return RouteResponse(status: .unauthorized, headers: [("Content-Type", "application/json")], body: data)
		}

		guard let body = request.body else {
			return RouteResponse(status: .badRequest)
		}

		do {
			let arguments = try MCPJSONCoding.makeDecoder().decode(JSONDictionary.self, from: body)
			let result: Encodable & Sendable
			let metadata: MCPToolMetadata?

			if let toolProvider = server as? MCPToolProviding,
			   toolProvider.mcpToolMetadata.contains(where: { $0.name == toolName }) {
				metadata = toolProvider.mcpToolMetadata.first(where: { $0.name == toolName })
				result = try await toolProvider.callTool(toolName, arguments: arguments)
			} else if let resourceProvider = server as? MCPResourceProviding,
					  resourceProvider.mcpResourceMetadata.contains(where: { $0.functionMetadata.name == toolName }) {
				metadata = nil
				result = try await resourceProvider.callResourceAsFunction(toolName, arguments: arguments)
			} else if let promptProvider = server as? MCPPromptProviding,
					  promptProvider.mcpPromptMetadata.contains(where: { $0.name == toolName }) {
				metadata = nil
				let messages = try await promptProvider.callPrompt(toolName, arguments: arguments)
				result = messages
			} else {
				throw MCPToolError.unknownTool(name: toolName)
			}

			let wrappedResult = try metadata?.wrapOutputIfNeeded(result) ?? result

			let responseToEncode: Encodable
			if let toolResult = wrappedResult as? MCPText {
				responseToEncode = toolResult
			} else if let toolResult = wrappedResult as? MCPImage {
				responseToEncode = toolResult
			} else if let toolResult = wrappedResult as? MCPAudio {
				responseToEncode = toolResult
			} else if let toolResult = wrappedResult as? MCPResourceLink {
				responseToEncode = toolResult
			} else if let toolResult = wrappedResult as? MCPEmbeddedResource {
				responseToEncode = toolResult
			} else if let toolResults = wrappedResult as? [MCPText] {
				responseToEncode = toolResults
			} else if let toolResults = wrappedResult as? [MCPImage] {
				responseToEncode = toolResults
			} else if let toolResults = wrappedResult as? [MCPAudio] {
				responseToEncode = toolResults
			} else if let toolResults = wrappedResult as? [MCPResourceLink] {
				responseToEncode = toolResults
			} else if let toolResults = wrappedResult as? [MCPEmbeddedResource] {
				responseToEncode = toolResults
			} else if let resourceContent = wrappedResult as? MCPResourceContent {
				responseToEncode = MCPEmbeddedResource(resource: resourceContent)
			} else if let resourceContentArray = wrappedResult as? [MCPResourceContent] {
				responseToEncode = resourceContentArray.map { MCPEmbeddedResource(resource: $0) }
			} else {
				responseToEncode = wrappedResult
			}

			let encoder = MCPJSONCoding.makeValueEncoder()
			encoder.outputFormatting = [.prettyPrinted]
			let jsonData = try encoder.encode(responseToEncode)
			return RouteResponse(status: .ok, headers: [("Content-Type", "application/json")], body: jsonData)

		} catch {
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
				error: .init(code: -32000, message: localizedDescription, data: errorData)
			)

			let data = try! JSONEncoder().encode(err)

			var status: HTTPStatus = .badRequest
			if let mcpError = error as? MCPToolError, case .unknownTool(_) = mcpError {
				status = .notFound
			}

			return RouteResponse(status: status, headers: [("Content-Type", "application/json")], body: data)
		}
	}
}
