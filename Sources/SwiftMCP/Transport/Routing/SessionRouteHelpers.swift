#if Server
import Foundation
import HTTPTypes

extension HTTPSSETransport {
    enum SessionHeaderResolution {
        case missing
        case malformed(String)
        case unknown(UUID)
        case existing(UUID)
    }

    func resolveSessionHeader<Body: Sendable>(for request: HTTPRouteRequest<Body>) async -> SessionHeaderResolution {
        guard let rawSessionID = request.sessionID else {
            return .missing
        }

        guard let sessionID = UUID(uuidString: rawSessionID) else {
            return .malformed(rawSessionID)
        }

        if await sessionManager.hasSession(id: sessionID) {
            return .existing(sessionID)
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

    func sessionNeedsInitialize(_ sessionID: UUID) async -> Bool {
        guard let session = await sessionManager.existingSession(id: sessionID) else {
            return false
        }

        return !(await session.hasReceivedInitializeRequest)
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
