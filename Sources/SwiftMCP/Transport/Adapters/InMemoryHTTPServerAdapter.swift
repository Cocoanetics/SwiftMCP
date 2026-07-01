//
//  InMemoryHTTPServerAdapter.swift
//  SwiftMCP
//
//  A socket-free adapter behind the ``MCPHTTPEngine`` seam. It drives the engine
//  directly — no swift-nio, no listener, no HTTP parsing — proving the engine is
//  transport-agnostic and giving tests a hermetic way to exercise the full MCP
//  HTTP/SSE surface without binding a port. A future Network.framework adapter is
//  the same shape with a real socket underneath.
//

#if Server
import Foundation
import HTTPTypes

public final class InMemoryHTTPServerAdapter: Sendable {
    private let engine: any MCPHTTPEngine

    public init(engine: any MCPHTTPEngine) {
        self.engine = engine
    }

    /// The body of an ``Exchange``: either a fully-buffered reply or an open SSE
    /// byte stream the caller drains (exactly the bytes the engine produced —
    /// every `data:` frame, in order).
    public enum ExchangeBody: Sendable {
        case buffered(Data?)
        case sse(AsyncStream<Data>)
    }

    /// One HTTP exchange: the response status and headers, plus the body.
    public struct Exchange: Sendable {
        public let status: HTTPResponse.Status
        public let headerFields: HTTPFields
        public let body: ExchangeBody
        /// The live connection for an SSE response, so a caller can force a
        /// disconnect and assert the engine retains the stream for resume.
        public let connection: InMemorySSEConnection?
    }

    /// Send one request through the engine and return its response. The whole body
    /// is fed up front; for an SSE response the returned stream yields each event
    /// the engine writes and ends when the engine finishes the stream (a buffered
    /// per-request reply) or when the connection is terminated (a general stream).
    public func send(
        method: HTTPRequest.Method,
        path: String,
        headerFields: HTTPFields = [:],
        body: Data? = nil
    ) async -> Exchange {
        // The engine reads the target from the request's `:path` pseudo-header and
        // reconstructs `Host` from `:authority` — mirroring what the HTTP/1 codec
        // hands the NIO adapter.
        let head = HTTPRequest(
            method: method, scheme: "http", authority: "memory",
            path: path, headerFields: headerFields
        )

        // Body-size enforcement is the adapter's job (per `MCPHTTPEngine`), so
        // reject an oversized body with a 413 *before* dispatching — exactly what
        // the NIO adapter does. The whole body is known up front here, so a single
        // check covers both of NIO's gates (declared `Content-Length` + accumulated
        // bytes). The shared helper keeps the reply byte-identical to NIO's.
        let sizeLimit = engine.maxBodySize(for: head)
        if let body, body.count > sizeLimit {
            let reply = HTTPResponseDefaults.oversizedBody(limit: sizeLimit)
            return Exchange(
                status: reply.status, headerFields: reply.headerFields,
                body: .buffered(reply.body), connection: nil
            )
        }

        let (bodyStream, bodyContinuation) = AsyncStream<Data>.makeStream()
        if let body, !body.isEmpty {
            bodyContinuation.yield(body)
        }
        bodyContinuation.finish()

        let response = await engine.handle(head: head, bodyStream: bodyStream)

        // Apply the same default response fields the NIO adapter writes (CORS
        // origin, and `Content-Type`/`Content-Length` for buffered replies), so a
        // caller observes byte-identical headers through either adapter.
        switch response.body {
        case .buffered(let data):
            let fields = HTTPResponseDefaults.buffered(response.headerFields, bodyLength: data?.count)
            return Exchange(
                status: response.status, headerFields: fields,
                body: .buffered(data), connection: nil
            )

        case .sse(let stream, let registration):
            var connection: InMemorySSEConnection?
            if let registration {
                let conn = InMemorySSEConnection()
                if let token = await engine.registerConnection(conn, for: registration) {
                    conn.bind { [engine] in await engine.connectionDisconnected(token) }
                }
                connection = conn
            }
            let fields = HTTPResponseDefaults.streaming(response.headerFields)
            return Exchange(
                status: response.status, headerFields: fields,
                body: .sse(stream), connection: connection
            )
        }
    }
}

/// An ``SSEConnection`` backed by an in-memory flag instead of a socket. Calling
/// ``terminate()`` flips it disconnected and fires the engine's disconnect hook,
/// mirroring the NIO adapter's `closeFuture` wiring.
public final class InMemorySSEConnection: SSEConnection, @unchecked Sendable {
    private let lock = NSLock()
    private var connected = true
    private var onClose: (@Sendable () async -> Void)?

    public init() {}

    public var isConnected: Bool { lock.withLock { connected } }

    public func terminate() {
        let callback: (@Sendable () async -> Void)?
        lock.lock()
        connected = false
        callback = onClose
        onClose = nil
        lock.unlock()
        if let callback {
            Task { await callback() }
        }
    }

    /// Wire the engine's disconnect callback, run when the connection terminates.
    func bind(_ onClose: @escaping @Sendable () async -> Void) {
        lock.withLock { self.onClose = onClose }
    }
}
#endif
