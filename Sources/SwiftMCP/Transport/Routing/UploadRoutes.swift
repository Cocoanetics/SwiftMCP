import Foundation


/// Upload route handlers.
extension HTTPSSETransport {

	/// Returns the upload-related routes.
	func uploadRoutes() -> [HTTPRoute] {
		[
			// POST /mcp/uploads/:cid — binary file upload (streaming input)
			HTTPRoute(.POST, "/mcp/uploads/:cid",
				calling: HTTPSSETransport.handleUpload),
		]
	}

	// MARK: - Handler Implementations

	/// Handle a file upload — body chunks arrive as a stream and are appended to a temp file.
	func handleUpload(request: HTTPRouteRequest<AsyncStream<Data>>) async throws -> RouteResponse {
		guard server is MCPFileUploadHandling else {
			return RouteResponse(status: .notFound, body: Data("File uploads not supported by this server.".utf8))
		}

		let sessionID = UUID(uuidString: request.sessionID ?? "") ?? UUID()

		let token = request.bearerToken

		let authResult = await authorize(token, sessionID: sessionID)
		switch authResult {
		case .unauthorized(let message):
			return RouteResponse(status: .unauthorized, body: Data("Unauthorized: \(message)".utf8))
		case .jweNotSupported(let message):
			return RouteResponse(status: .forbidden, body: Data(message.utf8))
		case .authorized:
			break
		}

		// Extract CID from path
		let pathComponents = request.uri.split(separator: "/")
		guard pathComponents.count >= 3,
			  pathComponents[0] == "mcp",
			  pathComponents[1] == "uploads",
			  let cid = String(pathComponents[2]).removingPercentEncoding else {
			return RouteResponse(status: .badRequest, body: Data("Missing CID in upload path. Use POST /mcp/uploads/{cid}".utf8))
		}

		// Stream body chunks to a temp file
		let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("mcp-upload-\(UUID().uuidString).bin")
		FileManager.default.createFile(atPath: tempURL.path, contents: nil)
		guard let handle = FileHandle(forWritingAtPath: tempURL.path) else {
			return RouteResponse(status: .internalServerError, body: Data("Failed to create temp file.".utf8))
		}
		var byteCount = 0
		for await chunk in request.body {
			handle.write(chunk)
			byteCount += chunk.count
		}
		try handle.close()

		guard byteCount > 0 else {
			try? FileManager.default.removeItem(at: tempURL)
			return RouteResponse(status: .badRequest, body: Data("Request body required.".utf8))
		}

		// Send progress notification
		let totalBytes = byteCount
		if let progressToken = await pendingUploadStore.progressToken(for: cid) {
			let session = await sessionManager.session(id: sessionID)
			await session.work { session in
				await session.sendProgressNotification(
					progressToken: progressToken,
					progress: Double(totalBytes),
					total: Double(totalBytes),
					message: "Upload received (\(totalBytes) bytes)"
				)
			}
		}

		// Fulfill the pending upload
		let fulfillResult = await pendingUploadStore.fulfill(cid: cid, fileURL: tempURL)
		if case .missed = fulfillResult {
			try? FileManager.default.removeItem(at: tempURL)
		}

		let statusString: String
		switch fulfillResult {
		case .fulfilled: statusString = "fulfilled"
		case .earlyArrival: statusString = "buffered"
		case .missed: statusString = "missed"
		}

		let responseDict: JSONDictionary = [
			"cid": .string(cid),
			"size": .integer(byteCount),
			"status": .string(statusString)
		]

		let encoder = JSONEncoder()
		encoder.outputFormatting = [.sortedKeys]
		guard let jsonData = try? encoder.encode(responseDict) else {
			return RouteResponse(status: .internalServerError, body: Data("{\"error\":\"Failed to encode response\"}".utf8))
		}

		logger.info("CID upload \(statusString): \(cid) (\(byteCount) bytes)")
		return RouteResponse(status: .ok, headers: [
			("Content-Type", "application/json"),
			("Mcp-Session-Id", sessionID.uuidString)
		], body: jsonData)
	}
}
