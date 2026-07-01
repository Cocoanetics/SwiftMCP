//
//  MCPHTTPEngine.swift
//  SwiftMCP
//
//  The seam between the NIO-free HTTP/SSE *engine* (routing, sessions, SSE) and a
//  socket-bound *adapter* (the listener, HTTP framing, and the read/write loops).
//  This file is HTTPTypes-only and imports no swift-nio, so the engine compiles
//  without the NIO server stack; only the adapters under `Transport/Adapters/`
//  link NIO.
//

#if Server
import Foundation
import HTTPTypes

/// A live SSE connection as the engine sees it.
///
/// The engine never writes bytes through this — outbound SSE data flows out the
/// response's `AsyncStream<Data>` continuation, which the adapter drains to the
/// socket. The handle exists only so the engine can test liveness (for the
/// active-stream/primary-stream bookkeeping) and force the connection closed on
/// teardown. The NIO adapter backs it with a `Channel`; the in-memory adapter
/// backs it with a flag.
public protocol SSEConnection: Sendable {
    /// Whether the underlying connection is still open.
    var isConnected: Bool { get }

    /// Force the connection closed (transport teardown).
    func terminate()
}

/// Identifies a bound SSE connection for disconnect bookkeeping.
///
/// Carries both the stream id and the per-connection dedup token, so a stale
/// close signal (from a connection that has already been replaced by a reconnect)
/// cannot tear down the newer stream.
public struct SSEConnectionToken: Sendable, Hashable {
    public let streamID: UUID
    public let connectionToken: UUID

    public init(streamID: UUID, connectionToken: UUID) {
        self.streamID = streamID
        self.connectionToken = connectionToken
    }
}

/// Where a streaming SSE response should be registered — the session and stream
/// it belongs to — so the adapter can bind the live connection after it has
/// written the response head.
public struct SSERegistration: Sendable, Hashable {
    public let sessionID: UUID
    public let streamID: UUID

    public init(sessionID: UUID, streamID: UUID) {
        self.sessionID = sessionID
        self.streamID = streamID
    }
}

/// The engine's reply to one inbound HTTP request: either a buffered body or an
/// open SSE byte stream the adapter drains.
public struct EngineResponse: Sendable {
    public var status: HTTPResponse.Status
    public var headerFields: HTTPFields

    public enum Body: Sendable {
        /// A complete response body (possibly empty).
        case buffered(Data?)
        /// An SSE stream the adapter writes as it yields, optionally registering
        /// the live connection (so the engine can push to and close it).
        case sse(stream: AsyncStream<Data>, registration: SSERegistration?)
    }

    public var body: Body

    public init(status: HTTPResponse.Status, headerFields: HTTPFields, body: Body) {
        self.status = status
        self.headerFields = headerFields
        self.body = body
    }
}

/// The NIO-free core that an HTTP server adapter drives.
///
/// The adapter owns the socket, HTTP framing, and the read/write loops; the
/// engine owns routing, sessions, and SSE. For each inbound request the adapter
/// calls ``handle(head:bodyStream:)`` and writes back the ``EngineResponse``; for
/// an SSE response it binds the live connection via ``registerConnection(_:for:)``
/// and reports the socket closing through ``connectionDisconnected(_:)``. Swapping
/// swift-nio for Network.framework (or an in-memory test rig) is implementing this
/// protocol's *caller* — the engine is untouched.
public protocol MCPHTTPEngine: AnyObject, Sendable {
    /// The host the adapter should bind to.
    var configuredHost: String { get }

    /// The port the adapter should bind to (`0` selects an ephemeral port).
    var configuredPort: Int { get }

    /// The maximum request-body size for the route matching `head`, in bytes.
    /// The adapter enforces it while reading the body.
    func maxBodySize(for head: HTTPRequest) -> Int

    /// Route and dispatch one request, returning the response to write back.
    func handle(head: HTTPRequest, bodyStream: AsyncStream<Data>) async -> EngineResponse

    /// Bind a live connection to a freshly-opened SSE stream, returning the token
    /// a later disconnect must present. `nil` if the stream is already gone.
    func registerConnection(
        _ connection: any SSEConnection, for registration: SSERegistration
    ) async -> SSEConnectionToken?

    /// Report that an SSE connection's socket has closed, so the engine can retain
    /// the stream for resume.
    func connectionDisconnected(_ token: SSEConnectionToken) async
}

/// HTTP response-shaping shared by every adapter, so a buffered reply gets the
/// same default CORS / `Content-Type` / `Content-Length` fields regardless of
/// which transport writes it. Pure (HTTPTypes-only).
public enum HTTPResponseDefaults {
    /// Apply the framework's default response fields without overwriting values
    /// the route already provided. `HTTPFields` is case-insensitive and replaces
    /// rather than appends, so defaults can never duplicate an existing field.
    public static func buffered(_ fields: HTTPFields, bodyLength: Int?) -> HTTPFields {
        var fields = fields

        if fields[.accessControlAllowOrigin] == nil {
            fields[.accessControlAllowOrigin] = "*"
        }

        if let bodyLength {
            if fields[.contentType] == nil {
                fields[.contentType] = "text/plain; charset=utf-8"
            }
            if fields[.contentLength] == nil {
                fields[.contentLength] = "\(bodyLength)"
            }
        } else if fields[.contentLength] == nil {
            fields[.contentLength] = "0"
        }

        return fields
    }

    /// Apply the default CORS origin to a streaming (SSE) response, leaving an
    /// explicit value intact. Streaming responses never carry `Content-Length`.
    public static func streaming(_ fields: HTTPFields) -> HTTPFields {
        var fields = fields
        if fields[.accessControlAllowOrigin] == nil {
            fields[.accessControlAllowOrigin] = "*"
        }
        return fields
    }
}
#endif
