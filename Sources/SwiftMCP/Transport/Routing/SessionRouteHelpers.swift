#if Server
import Foundation
import HTTPTypes

extension HTTPSSETransport {
    enum SessionHeaderResolution {
        case missing
        case malformed(String)
        case unknown(UUID)
        /// The session the header names, as the request found it: the request runs on this
        /// session, not on whatever is kept under its id later — nothing, once its client is
        /// disconnected (``SessionManager/disconnectSession(_:)``).
        case existing(Session)
    }

    func resolveSessionHeader<Body: Sendable>(for request: HTTPRouteRequest<Body>) async -> SessionHeaderResolution {
        guard let rawSessionID = request.sessionID else {
            return .missing
        }

        guard let sessionID = UUID(uuidString: rawSessionID) else {
            return .malformed(rawSessionID)
        }

        if let session = await sessionManager.existingSession(id: sessionID) {
            return .existing(session)
        }

        return .unknown(sessionID)
    }

    /// Whether an inbound HTTP request declares the modern era, from its
    /// `MCP-Protocol-Version` header. Modern is stateless/sessionless, so the
    /// header (not a session) is the reliable per-request era signal at the
    /// transport layer, before any body `_meta` is parsed.
    func requestDeclaresModern<Body: Sendable>(_ request: HTTPRouteRequest<Body>) -> Bool {
        guard let headerVersion = request.header("MCP-Protocol-Version") else {
            return false
        }
        return MCPProtocolVersion.isModern(headerVersion)
    }

    func sessionNeedsInitialize(_ session: Session) async -> Bool {
        !(await session.hasReceivedInitializeRequest)
    }

    /// Run authorization for an inbound request and return an error response (if any).
    func authorizeRequest(token: String?, authSessionID: UUID?) async -> RouteResponse? {
        let authResult = await authorize(token, sessionID: authSessionID)
        switch authResult {
        case .unauthorized(let message):
            let errorMessage = JSONRPCMessage.errorResponse(
                id: nil,
                error: .init(code: -32000, message: "Unauthorized: \(message)")
            )
            return .json(errorMessage, status: .unauthorized, sessionId: authSessionID?.uuidString)
        case .jweNotSupported(let message):
            let errorMessage = JSONRPCMessage.errorResponse(id: nil, error: .init(code: -32000, message: message))
            return .json(errorMessage, status: .forbidden, sessionId: authSessionID?.uuidString)
        case .authorized:
            return nil
        }
    }

    /// The answer to a request whose session is gone since it was admitted — its client
    /// disconnected: the same as had it come after.
    func unknownSessionResponse() -> RouteResponse {
        textResponse(status: .notFound, body: "Unknown session. Send initialize first.")
    }

    func batchContainsRequests(_ messages: [JSONRPCMessage]) -> Bool {
        messages.contains {
            if case .request = $0 {
                return true
            }
            return false
        }
    }

    func validateHTTPProtocolVersion<Body: Sendable>(
        for request: HTTPRouteRequest<Body>,
        sessionID: UUID?
    ) async -> RouteResponse? {
        if let headerVersion = request.header("MCP-Protocol-Version") {
            guard MCPProtocolVersion.isServable(headerVersion) else {
                return textResponse(status: .badRequest, body: "Invalid or unsupported MCP-Protocol-Version header.")
            }

            if let sessionID,
               let session = await sessionManager.existingSession(id: sessionID),
               let negotiatedVersion = await session.negotiatedProtocolVersion,
               negotiatedVersion != headerVersion {
                return textResponse(
                    status: .badRequest,
                    body: "MCP-Protocol-Version does not match the negotiated session version.",
                    sessionID: sessionID
                )
            }

            return nil
        }

        return nil
    }

    func resolvedHTTPProtocolVersion<Body: Sendable>(
        for request: HTTPRouteRequest<Body>,
        sessionID: UUID?,
        messages: [JSONRPCMessage] = []
    ) async -> String {
        if let headerVersion = request.header("MCP-Protocol-Version"),
           MCPProtocolVersion.isServable(headerVersion) {
            return headerVersion
        }

        if let sessionID,
           let session = await sessionManager.existingSession(id: sessionID),
           let negotiatedVersion = await session.negotiatedProtocolVersion {
            return negotiatedVersion
        }

        // A brand-new session has neither header nor stored version yet; the
        // version it is negotiating is declared inside the leading `initialize`
        // request (defaulting to `latest`, as `handleInitializeRequest` does).
        // Honour it so the rest of the batch is gated against that version.
        if SessionInitializationGate.batchStartsWithInitialize(messages) {
            return SessionInitializationGate.initializeProtocolVersion(messages) ?? MCPProtocolVersion.latest
        }

        return MCPProtocolVersion.fallbackHTTP
    }

    func bindBearerTokenIfNeeded(_ token: String?, to sessionID: UUID) async {
        guard let token else {
            return
        }

        guard let session = await sessionManager.existingSession(id: sessionID) else {
            return
        }

        if let storedToken = await session.accessToken,
           storedToken == token,
           (await session.accessTokenExpiry ?? Date.distantFuture) > Date() {
            return
        }

        guard await validateNewToken(token) else {
            return
        }

        await session.setAccessToken(token)
        await session.setAccessTokenExpiry(Date().addingTimeInterval(24 * 60 * 60))

        if let oauthConfiguration {
            await sessionManager.fetchAndStoreUserInfo(for: sessionID, oauthConfiguration: oauthConfiguration)
        }
    }

    func textResponse(status: HTTPResponse.Status, body: String, sessionID: UUID? = nil) -> RouteResponse {
        var headerFields: HTTPFields = [.contentType: "text/plain; charset=utf-8"]

        if let sessionID {
            headerFields[.mcpSessionID] = sessionID.uuidString
        }

        return RouteResponse(status: status, headerFields: headerFields, body: Data(body.utf8))
    }
}
#endif
