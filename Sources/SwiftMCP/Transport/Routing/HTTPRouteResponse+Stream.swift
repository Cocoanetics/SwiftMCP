#if Server
//
//  HTTPRouteResponse+Stream.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 02.04.26.
//

import Foundation
import HTTPTypes

// MARK: - Factories for AsyncStream<Data> body

extension HTTPRouteResponse where Body == AsyncStream<Data> {

	/// Stream a file from disk in chunks.
	///
	/// The stream is pull-based: each chunk is read only when the consumer
	/// demands the next element. An eager producer would queue the entire
	/// file into the stream whenever the client drains slower than disk
	/// reads — body-sized memory growth that consumer-side backpressure
	/// cannot prevent.
	public static func file(_ url: URL, contentType: String, chunkSize: Int = 65536) -> Self {
		let reader = ChunkedFileReader(url: url, chunkSize: chunkSize)
		return HTTPRouteResponse(
			status: .ok,
			headerFields: [.contentType: contentType],
			body: AsyncStream(unfolding: { await reader.next() })
		)
	}

	/// Wrap an existing async stream as an event stream response.
	public static func eventStream(_ source: AsyncStream<Data>) -> Self {
		HTTPRouteResponse(
			status: .ok,
			headerFields: [.contentType: "text/event-stream", .cacheControl: "no-cache"],
			body: source
		)
	}
}
#endif
