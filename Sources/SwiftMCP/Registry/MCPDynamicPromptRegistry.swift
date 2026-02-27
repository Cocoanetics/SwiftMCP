import Foundation

public enum MCPDynamicPromptRegistry {
    public typealias DynamicCall = @Sendable (AnyObject, [String: Sendable]) async throws -> [PromptMessage]
    public typealias DynamicMetadata = @Sendable (AnyObject) -> MCPPromptMetadata

    private struct DynamicPrompt {
        let metadata: DynamicMetadata
        let call: DynamicCall
    }

    private static let lock = NSLock()
    private nonisolated(unsafe) static var storage: [ObjectIdentifier: [String: DynamicPrompt]] = [:]

    public static func register<Server: AnyObject>(
        _ serverType: Server.Type,
        name: String,
        metadata: @escaping @Sendable (Server) -> MCPPromptMetadata,
        call: @escaping @Sendable (Server, [String: Sendable]) async throws -> [PromptMessage]
    ) {
        let key = ObjectIdentifier(serverType)
        let wrapped = DynamicPrompt(
            metadata: { anyServer in
                guard let typed = anyServer as? Server else {
                    return MCPPromptMetadata(
                        name: name,
                        description: "Type mismatch in dynamic MCP prompt registry",
                        parameters: [],
                        isAsync: true,
                        isThrowing: true
                    )
                }
                return metadata(typed)
            },
            call: { anyServer, args in
                guard let typed = anyServer as? Server else {
                    throw MCPToolError.unknownTool(name: name)
                }
                return try await call(typed, args)
            }
        )

        lock.lock()
        defer { lock.unlock() }

        var prompts = storage[key, default: [:]]
        if prompts[name] != nil {
            preconditionFailure("Duplicate MCP prompt registration for \(Server.self).\(name)")
        }
        prompts[name] = wrapped
        storage[key] = prompts
    }

    public static func metadata(for server: AnyObject) -> [MCPPromptMetadata] {
        lock.lock()
        let prompts = storage[ObjectIdentifier(type(of: server))]?.values.map { $0 } ?? []
        lock.unlock()
        return prompts.map { $0.metadata(server) }
    }

    public static func callIfRegistered(
        server: AnyObject,
        name: String,
        arguments: [String: Sendable]
    ) async throws -> [PromptMessage]? {
        guard let prompt = lookupPrompt(server: server, name: name) else {
            return nil
        }
        return try await prompt.call(server, arguments)
    }

    private static func lookupPrompt(server: AnyObject, name: String) -> DynamicPrompt? {
        lock.lock()
        defer { lock.unlock() }
        return storage[ObjectIdentifier(type(of: server))]?[name]
    }
}
