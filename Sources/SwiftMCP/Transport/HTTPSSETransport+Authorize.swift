import Foundation

extension HTTPSSETransport {
    /// Perform authorization using either the OAuth configuration or the
    /// synchronous ``authorizationHandler`` closure.
    func authorize(_ token: String?, sessionID: UUID?) async -> AuthorizationResult {
        // Check for JWE tokens first (5 segments: header.encrypted_key.iv.ciphertext.tag)
        if let jweResult = checkJWERejection(token: token) {
            return jweResult
        }

        // 1. If we have a session ID, check token against session-stored value
        if let id = sessionID, let session = await sessionManager.existingSession(id: id) {
            return await authorizeForExistingSession(token: token, sessionID: id, session: session)
        }

        // 2. If we don't have a sessionID, see if we can locate a session by token.
        if let token, sessionID == nil {
            if await sessionManager.session(forToken: token) != nil {
                return .authorized
            }
        }

        // 3. For tokens without session context, validate them
        if let token {
            let isValid = await validateNewToken(token)
            return isValid ? .authorized : .unauthorized("Invalid token - token exchange required")
        }

        // 4. If OAuth is configured, require authentication
        if oauthConfiguration != nil {
            guard let token = token, !token.isEmpty else {
                return .unauthorized("Authentication required")
            }
            return .unauthorized("Invalid token - token exchange required")
        }

        // 5. Otherwise use legacy handler (for unauthenticated mode)
        return authorizationHandler(token)
    }

    /// Checks for JWE tokens (5 segments) and returns rejection result if not in proxy mode.
    private func checkJWERejection(token: String?) -> AuthorizationResult? {
        guard let token else { return nil }
        let segments = token.split(separator: ".")
        guard segments.count == 5 else { return nil }

        // JWE token detected - only allow in proxy mode
        if let oauthConfiguration, oauthConfiguration.transparentProxy {
            // In proxy mode, we can handle JWE tokens by proxying them
            return nil
        }

        // In non-proxy mode, JWE tokens are not supported
        let audience = oauthConfiguration?.audience ?? "your-api"
        return .jweNotSupported(
            "Encrypted (JWE) tokens are not supported. "
                + "Use a signed JWT (JWS) with audience=\(audience)"
        )
    }

    /// Authorizes a request against an already-known session.
    private func authorizeForExistingSession(
        token: String?,
        sessionID: UUID,
        session: Session
    ) async -> AuthorizationResult {
        if let stored = await session.accessToken {
            if stored == token, (await session.accessTokenExpiry ?? Date.distantFuture) > Date() {
                return .authorized
            } else {
                return .unauthorized("Invalid or expired token")
            }
        }

        if let token {
            // First time we see a token for this session - validate it before accepting
            let isValid = await validateNewToken(token)
            if isValid {
                await session.setAccessToken(token)
                // Without expires_in we can't know exact lifetime; fall back to 24 h.
                await session.setAccessTokenExpiry(Date().addingTimeInterval(24 * 60 * 60))

                // Fetch and store user info if we have OAuth configuration
                if let oauthConfiguration {
                    await sessionManager.fetchAndStoreUserInfo(for: sessionID, oauthConfiguration: oauthConfiguration)
                }

                return .authorized
            } else {
                return .unauthorized("Invalid token - token exchange required")
            }
        }

        // No token provided for this session
        // If OAuth is configured, require authentication
        if oauthConfiguration != nil {
            return .unauthorized("Authentication required")
        }
        // Otherwise use legacy handler (for unauthenticated mode)
        return authorizationHandler(token)
    }

    /// Validate a new token using OAuth configuration or authorization handler
    internal func validateNewToken(_ token: String) async -> Bool {
        // If we have OAuth configuration, use its validation
        if let oauthConfiguration {
            // In transparent proxy mode, only accept tokens that are already stored in a session
            // This ensures we only trust tokens that came through our proxy
            if oauthConfiguration.transparentProxy {
                // Check if this token is already stored in any session
                if await sessionManager.session(forToken: token) != nil {
                    return true
                }
            }

            // Try OAuth validation for non-proxy mode
            let oauthValid = await oauthConfiguration.validate(token: token)
            if oauthValid {
                return true
            }

            return false
        }

        // Fallback to authorization handler
        switch authorizationHandler(token) {
        case .authorized:
            return true
        case .unauthorized:
            return false
        case .jweNotSupported:
            return false
        }
    }
}
