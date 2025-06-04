import Foundation

public struct MCPPromptMetadata: Sendable {
    public let functionMetadata: MCPFunctionMetadata

    public init(
        name: String,
        description: String? = nil,
        parameters: [MCPParameterInfo],
        isAsync: Bool = false,
        isThrowing: Bool = false
    ) {
        self.functionMetadata = MCPFunctionMetadata(
            name: name,
            description: description,
            parameters: parameters,
            returnType: nil,
            returnTypeDescription: nil,
            isAsync: isAsync,
            isThrowing: isThrowing
        )
    }

    public var name: String { functionMetadata.name }
    public var description: String? { functionMetadata.description }
    public var parameters: [MCPParameterInfo] { functionMetadata.parameters }
    public var isAsync: Bool { functionMetadata.isAsync }
    public var isThrowing: Bool { functionMetadata.isThrowing }

    public func enrichArguments(_ arguments: [String: Sendable]) throws -> [String: Sendable] {
        return try functionMetadata.enrichArguments(arguments)
    }
}
