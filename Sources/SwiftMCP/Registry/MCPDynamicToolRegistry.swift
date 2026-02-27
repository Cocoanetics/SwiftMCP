import Foundation

public enum MCPDynamicToolRegistry {
    public typealias DynamicCall = @Sendable (AnyObject, [String: Sendable]) async throws -> (Encodable & Sendable)
    public typealias DynamicMetadata = @Sendable (AnyObject) -> MCPToolMetadata

    private struct DynamicTool {
        let name: String
        let metadata: DynamicMetadata
        let call: DynamicCall
    }

    private static let lock = NSLock()
    private nonisolated(unsafe) static var storage: [ObjectIdentifier: [String: DynamicTool]] = [:]

    public static func register<Server: AnyObject>(
        _ serverType: Server.Type,
        name: String,
        metadata: @escaping @Sendable (Server) -> MCPToolMetadata,
        call: @escaping @Sendable (Server, [String: Sendable]) async throws -> (Encodable & Sendable)
    ) {
        let key = ObjectIdentifier(serverType)
        let wrapped = DynamicTool(
            name: name,
            metadata: { anyServer in
                guard let typed = anyServer as? Server else {
                    return MCPToolMetadata(
                        name: name,
                        description: "Type mismatch in dynamic MCP tool registry",
                        parameters: [],
                        returnType: String.self,
                        returnTypeDescription: nil,
                        isAsync: true,
                        isThrowing: true,
                        isConsequential: true,
                        annotations: nil
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

        var tools = storage[key, default: [:]]
        tools[name] = wrapped
        storage[key] = tools
    }

    public static func metadata(for server: AnyObject) -> [MCPToolMetadata] {
        lock.lock()
        let tools = storage[ObjectIdentifier(type(of: server))]?.values.map { $0 } ?? []
        lock.unlock()
        return tools.map { $0.metadata(server) }
    }

    public static func callIfRegistered(
        server: AnyObject,
        name: String,
        arguments: [String: Sendable]
    ) async throws -> (Encodable & Sendable)? {
        guard let tool = lookupTool(server: server, name: name) else {
            return nil
        }

        return try await tool.call(server, arguments)
    }

    private static func lookupTool(server: AnyObject, name: String) -> DynamicTool? {
        lock.lock()
        defer { lock.unlock() }
        return storage[ObjectIdentifier(type(of: server))]?[name]
    }
}
