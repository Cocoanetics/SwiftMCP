import Foundation

/// The cache scope of a cacheable result (SEP-2549).
public enum MCPCacheScope: String, Codable, Sendable {
    /// The result may be cached and shared across users.
    case `public`
    /// The result may only be cached for the requesting user.
    case `private`
}

/// Cache hint attached to cacheable results (`ttlMs` / `cacheScope`, SEP-2549).
public struct MCPCacheHint: Equatable, Sendable {
    /// How long, in milliseconds, the result may be cached. `0` means "don't cache".
    public var ttlMs: Int

    /// Who the result may be shared with.
    public var cacheScope: MCPCacheScope

    public init(ttlMs: Int, cacheScope: MCPCacheScope) {
        self.ttlMs = ttlMs
        self.cacheScope = cacheScope
    }

    /// The conservative default: don't cache, and never share across users.
    public static let `default` = MCPCacheHint(ttlMs: 0, cacheScope: .private)
}

/// The requests whose results carry cache hints.
public enum MCPCacheableMethod: String, Sendable {
    case toolsList = "tools/list"
    case promptsList = "prompts/list"
    case resourcesList = "resources/list"
    case resourcesRead = "resources/read"
    case resourceTemplatesList = "resources/templates/list"
    case serverDiscover = "server/discover"
}

/// Author hook for the `ttlMs` / `cacheScope` hints emitted on cacheable results
/// to modern (`2026-07-28`+) clients. Legacy responses never carry them.
public protocol MCPCacheHintProviding {
    /// The hint for `method`. The default is ``MCPCacheHint/default``.
    func cacheHint(for method: MCPCacheableMethod) async -> MCPCacheHint
}

public extension MCPCacheHintProviding {
    func cacheHint(for method: MCPCacheableMethod) async -> MCPCacheHint { .default }
}

extension MCPServer {
    /// Adds `ttlMs` / `cacheScope` to `fields` when the request's negotiated
    /// revision supports cacheable results; legacy results are returned as-is.
    func cacheableResult(_ fields: [String: JSONValue], for method: MCPCacheableMethod) async -> JSONValue {
        var fields = fields
        if await RequestContext.current?.supports(.cacheableListResults) ?? false {
            let hint = await (self as? MCPCacheHintProviding)?.cacheHint(for: method) ?? .default
            fields["ttlMs"] = .integer(hint.ttlMs)
            fields["cacheScope"] = .string(hint.cacheScope.rawValue)
        }
        return .object(fields)
    }
}
