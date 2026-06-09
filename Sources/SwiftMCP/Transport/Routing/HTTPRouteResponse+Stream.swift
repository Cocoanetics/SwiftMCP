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
	public static func file(_ url: URL, contentType: String, chunkSize: Int = 65536) -> Self {
		let (stream, continuation) = AsyncStream<Data>.makeStream()

		// Read the file in a background task
		Task {
			defer { continuation.finish() }
			guard let handle = try? FileHandle(forReadingFrom: url) else {
				return
			}
			defer { try? handle.close() }

			while true {
				let chunk = handle.readData(ofLength: chunkSize)
				if chunk.isEmpty { break }
				continuation.yield(chunk)
			}
		}

		return HTTPRouteResponse(
			status: .ok,
			headerFields: [.contentType: contentType],
			body: stream
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
