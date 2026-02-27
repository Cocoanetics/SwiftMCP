import Foundation

public enum MCPDynamicResourceRegistry {
    public typealias DynamicCall = @Sendable (AnyObject, [String: Sendable], URL, String?) async throws -> [MCPResourceContent]
    public typealias DynamicMetadata = @Sendable (AnyObject) -> MCPResourceMetadata

    private struct DynamicResource {
        let metadata: DynamicMetadata
        let call: DynamicCall
    }

    private static let lock = NSLock()
    private nonisolated(unsafe) static var storage: [ObjectIdentifier: [String: DynamicResource]] = [:]

    public static func register<Server: AnyObject>(
        _ serverType: Server.Type,
        name: String,
        metadata: @escaping @Sendable (Server) -> MCPResourceMetadata,
        call: @escaping @Sendable (Server, [String: Sendable], URL, String?) async throws -> [MCPResourceContent]
    ) {
        let key = ObjectIdentifier(serverType)
        let wrapped = DynamicResource(
            metadata: { anyServer in
                guard let typed = anyServer as? Server else {
                    return MCPResourceMetadata(
                        uriTemplates: [],
                        name: name,
                        functionName: name,
                        description: "Type mismatch in dynamic MCP resource registry",
                        parameters: [],
                        returnType: String.self,
                        returnTypeDescription: nil,
                        isAsync: true,
                        isThrowing: true,
                        mimeType: nil
                    )
                }
                return metadata(typed)
            },
            call: { anyServer, args, requestedUri, overrideMimeType in
                guard let typed = anyServer as? Server else {
                    throw MCPResourceError.notFound(uri: requestedUri.absoluteString)
                }
                return try await call(typed, args, requestedUri, overrideMimeType)
            }
        )

        lock.lock()
        defer { lock.unlock() }

        var resources = storage[key, default: [:]]
        if resources[name] != nil {
            preconditionFailure("Duplicate MCP resource registration for \(Server.self).\(name)")
        }
        resources[name] = wrapped
        storage[key] = resources
    }

    public static func metadata(for server: AnyObject) -> [MCPResourceMetadata] {
        lock.lock()
        let resources = storage[ObjectIdentifier(type(of: server))]?.values.map { $0 } ?? []
        lock.unlock()
        return resources.map { $0.metadata(server) }
    }

    public static func callIfRegistered(
        server: AnyObject,
        name: String,
        arguments: [String: Sendable],
        requestedUri: URL,
        overrideMimeType: String?
    ) async throws -> [MCPResourceContent]? {
        guard let resource = lookupResource(server: server, name: name) else {
            return nil
        }
        return try await resource.call(server, arguments, requestedUri, overrideMimeType)
    }

    private static func lookupResource(server: AnyObject, name: String) -> DynamicResource? {
        lock.lock()
        defer { lock.unlock() }
        return storage[ObjectIdentifier(type(of: server))]?[name]
    }
}
