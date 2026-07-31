#if Server
//
//  ChunkedFileReader.swift
//  SwiftMCP
//

import Foundation

/// Reads a file chunk-by-chunk on consumer demand for pull-based streaming.
///
/// The file is opened lazily on first demand and closed at end-of-file, on
/// read failure, and on deallocation — an abandoned stream (client abort)
/// never leaks the descriptor.
actor ChunkedFileReader {
	private let url: URL
	private let chunkSize: Int
	private var handle: FileHandle?
	private var finished = false

	init(url: URL, chunkSize: Int) {
		self.url = url
		self.chunkSize = max(chunkSize, 1)
	}

	deinit {
		try? handle?.close()
	}

	/// Returns the next chunk, or `nil` at end-of-file or when the file
	/// cannot be opened.
	func next() -> Data? {
		if finished {
			return nil
		}

		if handle == nil {
			guard let opened = try? FileHandle(forReadingFrom: url) else {
				finished = true
				return nil
			}
			handle = opened
		}

		let chunk = handle?.readData(ofLength: chunkSize) ?? Data()
		if chunk.isEmpty {
			finished = true
			try? handle?.close()
			handle = nil
			return nil
		}
		return chunk
	}
}
#endif
