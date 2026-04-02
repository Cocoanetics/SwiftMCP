import Testing
import Foundation
@testable import SwiftMCP


/// Thread-safe box for capturing values from @Sendable closures.
private final class Box<T: Sendable>: @unchecked Sendable {
	var value: T
	init(_ value: T) { self.value = value }
}


@Suite("Streaming Route Handler")
struct StreamingRouteTests {

	private func makeTransport() -> HTTPSSETransport {
		let server = Calculator()
		return HTTPSSETransport(server: server, host: "localhost", port: 0)
	}

	/// Helper: create a streaming request with pre-loaded chunks.
	private func makeStreamingRequest(
		path: String,
		method: RouteMethod = .POST,
		headers: [(String, String)] = [],
		pathParams: [String: String] = [:],
		chunks: [Data]
	) -> HTTPRouteRequest<AsyncStream<Data>> {
		let (stream, continuation) = AsyncStream<Data>.makeStream()
		for chunk in chunks {
			continuation.yield(chunk)
		}
		continuation.finish()

		return HTTPRouteRequest<AsyncStream<Data>>(
			method: method, uri: path, path: path,
			headers: headers, body: stream,
			pathParams: pathParams, queryParams: []
		)
	}

	// MARK: - Buffered handler collects stream into Data

	@Test("buffered handler receives all chunks as collected Data")
	func bufferedCollectsStream() async throws {
		let received = Box<Data?>(nil)

		let route = HTTPRoute(
			method: .POST,
			pathPattern: "/test",
			handler: { (_: HTTPSSETransport, request: HTTPRouteRequest<Data?>) in
				received.value = request.body
				return RouteResponse(status: .ok)
			}
		)

		let request = makeStreamingRequest(path: "/test", chunks: [
			Data("chunk1-".utf8),
			Data("chunk2-".utf8),
			Data("chunk3".utf8),
		])

		let response = try await route.handler(makeTransport(), request)
		#expect(response.status == .ok)
		#expect(received.value == Data("chunk1-chunk2-chunk3".utf8))
	}

	// MARK: - Streaming handler receives the stream directly

	@Test("streaming handler receives chunks individually")
	func streamingReceivesChunks() async throws {
		let received = Box<[Data]>([])

		let route = HTTPRoute(
			method: .POST,
			pathPattern: "/upload",
			handler: { (_: HTTPSSETransport, request: HTTPRouteRequest<AsyncStream<Data>>) in
				for await chunk in request.body {
					received.value.append(chunk)
				}
				return RouteResponse(status: .ok)
			}
		)

		let request = makeStreamingRequest(path: "/upload", chunks: [
			Data("aaa".utf8),
			Data("bbb".utf8),
			Data("ccc".utf8),
		])

		let response = try await route.handler(makeTransport(), request)
		#expect(response.status == .ok)
		#expect(received.value.count == 3)
		#expect(received.value[0] == Data("aaa".utf8))
		#expect(received.value[1] == Data("bbb".utf8))
		#expect(received.value[2] == Data("ccc".utf8))
	}

	// MARK: - Empty stream produces nil body for buffered handler

	@Test("buffered handler receives nil body for empty stream")
	func bufferedEmptyStream() async throws {
		let received = Box<Data?>(Data("sentinel".utf8))

		let route = HTTPRoute(
			method: .GET,
			pathPattern: "/empty",
			handler: { (_: HTTPSSETransport, request: HTTPRouteRequest<Data?>) in
				received.value = request.body
				return RouteResponse(status: .ok)
			}
		)

		let request = makeStreamingRequest(path: "/empty", method: .GET, chunks: [])

		let response = try await route.handler(makeTransport(), request)
		#expect(response.status == .ok)
		#expect(received.value == nil)
	}

	// MARK: - Metadata preserved through streaming

	@Test("streaming handler receives path params and headers")
	func streamingPreservesMetadata() async throws {
		let receivedCID = Box<String?>(nil)
		let receivedAuth = Box<String?>(nil)

		let route = HTTPRoute(
			method: .POST,
			pathPattern: "/uploads/:cid",
			handler: { (_: HTTPSSETransport, request: HTTPRouteRequest<AsyncStream<Data>>) in
				receivedCID.value = request.pathParams["cid"]
				receivedAuth.value = request.bearerToken
				for await _ in request.body {}
				return RouteResponse(status: .ok)
			}
		)

		let request = makeStreamingRequest(
			path: "/uploads/abc123",
			headers: [("Authorization", "Bearer my-token")],
			pathParams: ["cid": "abc123"],
			chunks: [Data("data".utf8)]
		)

		_ = try await route.handler(makeTransport(), request)
		#expect(receivedCID.value == "abc123")
		#expect(receivedAuth.value == "my-token")
	}
}
