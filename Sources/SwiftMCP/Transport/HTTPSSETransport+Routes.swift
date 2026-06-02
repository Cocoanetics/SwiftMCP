#if Server
import Foundation

extension HTTPSSETransport {
    // MARK: - Route Registration

    /// Register a route with buffered input and buffered output.
    ///
    /// - Parameter maxBodySize: Optional per-route body size limit in bytes.
    ///   When `nil`, requests are capped by the transport's ``maxMessageSize``.
    ///   Set this for routes that accept larger-than-default payloads.
    ///
    /// Must be called before ``start()``.
    public func addRoute(
        _ method: RouteMethod,
        _ path: String,
        maxBodySize: Int? = nil,
        handler: @escaping @Sendable (HTTPRouteRequest<Data?>) async throws -> HTTPRouteResponse<Data?>
    ) {
        customRoutes.append(HTTPRoute(
            method: method,
            pathPattern: path,
            maxBodySize: maxBodySize,
            handler: { _, request in
                RouteResponse(try await handler(request))
            }
        ))
    }

    /// Register a route with buffered input and streaming output.
    ///
    /// - Parameter maxBodySize: Optional per-route body size limit in bytes.
    ///   When `nil`, requests are capped by the transport's ``maxMessageSize``.
    ///
    /// Must be called before ``start()``.
    public func addRoute(
        _ method: RouteMethod,
        _ path: String,
        maxBodySize: Int? = nil,
        handler: @escaping @Sendable (HTTPRouteRequest<Data?>) async throws -> HTTPRouteResponse<AsyncStream<Data>>
    ) {
        customRoutes.append(HTTPRoute(
            method: method,
            pathPattern: path,
            maxBodySize: maxBodySize,
            handler: { _, request in
                RouteResponse(try await handler(request))
            }
        ))
    }

    /// Register a route with streaming input and buffered output.
    ///
    /// Each incoming body chunk is yielded on the handler's `AsyncStream<Data>` as
    /// it arrives from the underlying HTTP transport, without the full body being
    /// buffered first. Use this for uploads larger than memory, or when the handler
    /// needs to tee / forward chunks (e.g. to a remote resumable upload) while the
    /// client is still sending.
    ///
    /// The `streamingHandler:` label distinguishes the overload from the two
    /// buffered-input variants above.
    ///
    /// - Parameter maxBodySize: Optional per-route body size limit in bytes.
    ///   When `nil`, requests are capped by the transport's ``maxMessageSize``.
    ///
    /// Must be called before ``start()``.
    public func addRoute(
        _ method: RouteMethod,
        _ path: String,
        maxBodySize: Int? = nil,
        streamingHandler: @escaping @Sendable (HTTPRouteRequest<AsyncStream<Data>>) async throws
            -> HTTPRouteResponse<Data?>
    ) {
        customRoutes.append(HTTPRoute(
            method: method,
            pathPattern: path,
            maxBodySize: maxBodySize,
            handler: { _, request in
                RouteResponse(try await streamingHandler(request))
            }
        ))
    }

    /// Register a route with streaming input and streaming output.
    ///
    /// See ``addRoute(_:_:maxBodySize:streamingHandler:)-<Data?>`` for input behaviour.
    ///
    /// - Parameter maxBodySize: Optional per-route body size limit in bytes.
    ///   When `nil`, requests are capped by the transport's ``maxMessageSize``.
    ///
    /// Must be called before ``start()``.
    public func addRoute(
        _ method: RouteMethod,
        _ path: String,
        maxBodySize: Int? = nil,
        streamingHandler: @escaping @Sendable (HTTPRouteRequest<AsyncStream<Data>>) async throws
            -> HTTPRouteResponse<AsyncStream<Data>>
    ) {
        customRoutes.append(HTTPRoute(
            method: method,
            pathPattern: path,
            maxBodySize: maxBodySize,
            handler: { _, request in
                RouteResponse(try await streamingHandler(request))
            }
        ))
    }

    // MARK: - Router Assembly

    /// Build the router with all built-in and custom routes.
    internal func buildRouter() -> Router {
        let router = Router()

        // Built-in routes (order matters — first match wins)
        router.addRoutes(corsRoutes())
        router.addRoutes(mcpRoutes())
        router.addRoutes(legacySSERoutes())
        #if OpenAPI
        router.addRoutes(openAPIRoutes())
        #endif
        router.addRoutes(oauthRoutes())

        // Custom routes registered by the user
        router.addRoutes(customRoutes)
        return router
    }
}
#endif
