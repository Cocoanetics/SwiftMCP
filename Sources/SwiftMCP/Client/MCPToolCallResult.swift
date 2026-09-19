#if Client
import Foundation

/// Everything a `tools/call` answered with.
///
/// `callTool(_:arguments:)` keeps only the text block. This keeps the lot: the
/// structured value the tool's `outputSchema` describes, every content block
/// as sent, and `_meta`. A typed call decodes from `structuredContent` when it
/// is there and from the text block when it is not.
public struct MCPToolCallResult: Sendable {
    /// The content blocks, in order, exactly as the server sent them.
    public let content: [JSONValue]
    /// The value described by the tool's `outputSchema`, when the server sent one.
    public let structuredContent: JSONValue?
    /// The request's `_meta`, if any.
    public let meta: JSONDictionary?

    public init(content: [JSONValue], structuredContent: JSONValue? = nil, meta: JSONDictionary? = nil) {
        self.content = content
        self.structuredContent = structuredContent
        self.meta = meta
    }
}
#endif
