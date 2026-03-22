import NIOHTTP1
import NIOCore
import Foundation

/// Represents the state of an HTTP request being processed
enum RequestState {
    case idle
    case head(HTTPRequestHead)
    case body(head: HTTPRequestHead, data: ByteBuffer)
    /// Streaming upload: chunks are appended directly to a temp file.
    case upload(head: HTTPRequestHead, fileHandle: FileHandle, fileURL: URL, bytesWritten: Int)
    case rejected
} 
