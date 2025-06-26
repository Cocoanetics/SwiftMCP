# JWT Decoder for SwiftMCP

This implementation provides a lightweight JWT decoder and validator for the SwiftMCP project, designed to work without third-party dependencies.

## Features

- ✅ **Decode JWT tokens** with header, payload, and signature extraction
- ✅ **Validate JWT claims** including issuer (`iss`), audience (`aud`), expiration (`exp`), and not-before (`nbf`)
- ✅ **Clock skew tolerance** for handling time synchronization differences
- ✅ **Auth0 integration** with convenient configuration helpers
- ✅ **Comprehensive error handling** with descriptive error messages
- ✅ **Thread-safe** with Sendable conformance

## Basic Usage

### Decoding a JWT Token

```swift
import SwiftMCP

let decoder = JWTDecoder()
let jwt = try decoder.decode(tokenString)

// Access header information
print("Algorithm: \(jwt.header.alg)")
print("Key ID: \(jwt.header.kid ?? "none")")

// Access payload claims
print("Issuer: \(jwt.payload.iss ?? "unknown")")
print("Subject: \(jwt.payload.sub ?? "unknown")")
print("Expiration: \(jwt.payload.exp ?? Date.distantPast)")
```

### Validating a JWT Token

```swift
let options = JWTDecoder.ValidationOptions(
    expectedIssuer: "https://your-auth0-domain.auth0.com/",
    expectedAudience: "https://your-api-identifier",
    allowedClockSkew: 60 // seconds
)

do {
    let jwt = try decoder.decodeAndValidate(tokenString, options: options)
    print("Token is valid!")
} catch JWTDecoder.JWTError.expired {
    print("Token has expired")
} catch JWTDecoder.JWTError.invalidIssuer(let expected, let actual) {
    print("Invalid issuer. Expected: \(expected), Got: \(actual ?? "nil")")
} catch {
    print("Token validation failed: \(error)")
}
```

## Integration with OAuth

### Using JWTTokenValidator

```swift
let validator = JWTTokenValidator(
    expectedIssuer: "https://dev-8ygj6eppnvjz8bm6.us.auth0.com/",
    expectedAudience: "https://dev-8ygj6eppnvjz8bm6.us.auth0.com/api/v2/"
)

// Simple validation
let isValid = await validator.validate(tokenString)

// Extract user information
if let userInfo = validator.extractUserInfo(tokenString) {
    print("User ID: \(userInfo["sub"] ?? "unknown")")
    print("Scopes: \(userInfo["scope"] ?? "none")")
}
```

### Auth0 OAuth Configuration

```swift
let oauthConfig = OAuthConfiguration.auth0JWT(
    domain: "dev-8ygj6eppnvjz8bm6.us.auth0.com",
    expectedAudience: "https://dev-8ygj6eppnvjz8bm6.us.auth0.com/api/v2/",
    clientId: "your-client-id",
    clientSecret: "your-client-secret"
)

// Apply to your HTTP transport
transport.oauthConfiguration = oauthConfig
```

## Example: Your Actual Token

The decoder successfully handles your Auth0 JWT token:

```swift
let tokenFromRequest = "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCIsImtpZCI6ImlfRjhMWkdhRC10SkIzcm9MckRCMSJ9..."

let jwt = try decoder.decode(tokenFromRequest)

// Extracted information:
// - Algorithm: RS256
// - Key ID: i_F8LZGaD-tJB3roLrDB1
// - Issuer: https://dev-8ygj6eppnvjz8bm6.us.auth0.com/
// - Subject: auth0|685bfe07a54b24aa78b0ca2d
// - Audience: ["https://dev-8ygj6eppnvjz8bm6.us.auth0.com/api/v2/", "https://dev-8ygj6eppnvjz8bm6.us.auth0.com/userinfo"]
// - Scopes: "openid profile email"
// - Issued At: 1750882399 (Unix timestamp)
// - Expires: 1750968799 (Unix timestamp)
```

## Error Handling

The decoder provides specific error types for different validation failures:

```swift
enum JWTError: Error {
    case invalidFormat          // Malformed JWT structure
    case invalidBase64         // Base64 decoding failed
    case invalidJSON           // JSON parsing failed
    case expired               // Token has expired
    case notYetValid          // Token not yet valid (nbf claim)
    case invalidIssuer        // Issuer mismatch
    case invalidAudience      // Audience mismatch
}
```

## Security Notes

⚠️ **Important**: This decoder validates JWT structure and claims but does **NOT** verify cryptographic signatures. For production use, you should:

1. **Fetch the public key** from your Auth0 JWKS endpoint: `https://your-domain.auth0.com/.well-known/jwks.json`
2. **Verify the signature** using the public key that matches the token's `kid` header
3. **Implement proper key caching** and rotation handling

The current implementation is suitable for:
- Development and testing
- Scenarios where tokens are already validated by a trusted proxy
- Extracting claims from pre-validated tokens

## Testing

The implementation includes comprehensive tests covering:
- Token decoding with real Auth0 tokens
- Validation of various JWT claims
- Error handling for malformed tokens
- Clock skew tolerance
- Audience handling (single and multiple values)

Run the tests with:
```bash
swift test --filter JWTDecoderTests
```

## Integration with SwiftMCP Transport

The JWT decoder integrates seamlessly with the existing `HTTPSSETransport` authorization system:

```swift
// In your transport configuration
transport.oauthConfiguration = OAuthConfiguration.auth0JWT(
    domain: "your-auth0-domain.auth0.com",
    expectedAudience: "your-api-identifier",
    clientId: "your-client-id",
    clientSecret: "your-client-secret"
)
```

This automatically handles JWT validation for all incoming requests to your MCP server endpoints. 