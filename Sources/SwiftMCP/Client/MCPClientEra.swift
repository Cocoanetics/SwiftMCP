#if Client
import Foundation

/// The protocol era a connection operates in.
public enum MCPClientEra: String, Sendable {
    /// `2025-11-25` and earlier: `initialize` handshake, sessions.
    case legacy
    /// `2026-07-28`+: stateless, no handshake, per-request `_meta`.
    case modern
}

/// Which era ``MCPServerProxy/connect(clientName:clientVersion:)`` should use.
public enum MCPClientEraPreference: String, Sendable {
    /// Always run the legacy `initialize` handshake, without a `server/discover`
    /// probe. Pin this for servers that misbehave on unknown methods.
    case legacy
    /// Probe `server/discover` first; fall back to the legacy handshake when the
    /// server does not offer a modern revision this client supports. The default.
    case auto
    /// Require a modern revision; never send `initialize`.
    case modern
}

/// **Experimental.** Answers the input requests a modern server embeds in an
/// `input_required` result (MRTR) — the client-side replacement for live
/// `elicitation/create`, `sampling/createMessage` and `roots/list` requests.
public protocol MCPClientInputHandler: Sendable {
    /// The input request methods this handler can answer. They are also
    /// advertised in the per-request `clientCapabilities`.
    var supportedMethods: Set<String> { get }

    /// Produces the result for one input request: the same value a legacy client
    /// would have returned in the JSON-RPC response to `method`.
    func handleInput(method: String, params: JSONValue?) async throws -> JSONValue
}

public extension MCPClientInputHandler {
    var supportedMethods: Set<String> {
        ["elicitation/create", "sampling/createMessage", "roots/list"]
    }
}

/// Encodes tool arguments for the modern `Mcp-Param-{name}` request headers
/// (`x-mcp-header`).
enum MCPParamHeader {
    /// The header value mirroring `value`, or `nil` when it must not be mirrored
    /// (`null`). Printable-ASCII strings are sent verbatim; any other string —
    /// non-ASCII, control characters, or surrounding whitespace — becomes the
    /// `=?base64?<UTF-8 base64>?=` sentinel. Other values use compact JSON with
    /// sorted keys (`42`, `true`), matching the server's validator.
    static func encode(_ value: JSONValue) -> String? {
        if value == .null {
            return nil
        }
        if let string = value.stringValue {
            return isPlainHeaderText(string) ? string : sentinel(for: string)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return isPlainHeaderText(text) ? text : sentinel(for: text)
    }

    private static func isPlainHeaderText(_ string: String) -> Bool {
        guard string.unicodeScalars.allSatisfy({ (0x20...0x7E).contains($0.value) }) else {
            return false
        }
        return !string.hasPrefix(" ") && !string.hasSuffix(" ")
    }

    private static func sentinel(for string: String) -> String {
        "=?base64?\(Data(string.utf8).base64EncodedString())?="
    }
}
#endif
