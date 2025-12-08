import NIOHTTP1
import NIOCore

/// Represents the state of an HTTP request being processed
enum RequestState {
    case idle
    case head(HTTPRequestHead)
    case body(head: HTTPRequestHead, data: ByteBuffer)
    case rejected
} 
