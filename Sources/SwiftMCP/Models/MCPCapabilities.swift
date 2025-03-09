import Foundation

/// Represents a JSON-RPC 2.0 capabilities response message
public struct MCPCapabilitiesResponse: Codable {
    /// The JSON-RPC version
    public let jsonrpc: String
    
    /// The request identifier
    public let id: Int
    
    /// The result containing capabilities information
    public let result: MCPCapabilitiesResult
    
    /// Initialize a new capabilities response
    /// - Parameters:
    ///   - id: The request identifier
    ///   - result: The capabilities result
    public init(id: Int, result: MCPCapabilitiesResult) {
        self.jsonrpc = "2.0"
        self.id = id
        self.result = result
    }
    
    /// Create a default capabilities response
    /// - Returns: A pre-configured capabilities response
    public static func createDefault(tools: [MCPTool]? = nil) -> MCPCapabilitiesResponse {
        return MCPCapabilitiesResponse(
            id: 1,
            result: MCPCapabilitiesResult(
                protocol_version: "1.0",
                capabilities: MCPCapabilities(tools: tools),
                server_info: MCPServerInfo(
                    name: "MyServer",
                    version: "1.2"
                ),
                instructions: "Welcome to MyServer!"
            )
        )
    }
}

/// Represents the result part of a capabilities response
public struct MCPCapabilitiesResult: Codable {
    /// Optional metadata
    public let meta: String?
    
    /// The protocol version
    public let protocol_version: String
    
    /// The server capabilities
    public let capabilities: MCPCapabilities
    
    /// Information about the server
    public let server_info: MCPServerInfo
    
    /// Instructions for the client
    public let instructions: String
    
    /// Extra information as a dictionary
    public let extra: [String: String]
    
    /// Initialize a new capabilities result
    /// - Parameters:
    ///   - meta: Optional metadata
    ///   - protocol_version: The protocol version
    ///   - capabilities: The server capabilities
    ///   - server_info: Information about the server
    ///   - instructions: Instructions for the client
    ///   - extra: Extra information as a dictionary
    public init(
        meta: String? = nil,
        protocol_version: String,
        capabilities: MCPCapabilities = MCPCapabilities(),
        server_info: MCPServerInfo,
        instructions: String,
        extra: [String: String] = [:]
    ) {
        self.meta = meta
        self.protocol_version = protocol_version
        self.capabilities = capabilities
        self.server_info = server_info
        self.instructions = instructions
        self.extra = extra
    }
}

/// Represents the capabilities of the server
public struct MCPCapabilities: Codable {
    /// Experimental capabilities
    public let experimental: String?
    
    /// Logging capabilities
    public let logging: String?
    
    /// Prompts capabilities
    public let prompts: String?
    
    /// Resources capabilities
    public let resources: String?
    
    /// Tools available to the client
    public let tools: [MCPTool]?
    
    /// Extra capabilities as a dictionary
    public let extra: [String: String]
    
    /// Initialize new capabilities
    /// - Parameters:
    ///   - experimental: Experimental capabilities
    ///   - logging: Logging capabilities
    ///   - prompts: Prompts capabilities
    ///   - resources: Resources capabilities
    ///   - tools: Tools available to the client
    ///   - extra: Extra capabilities as a dictionary
    public init(
        experimental: String? = nil,
        logging: String? = nil,
        prompts: String? = nil,
        resources: String? = nil,
        tools: [MCPTool]? = nil,
        extra: [String: String] = [:]
    ) {
        self.experimental = experimental
        self.logging = logging
        self.prompts = prompts
        self.resources = resources
        self.tools = tools
        self.extra = extra
    }
}

/// Represents information about the server
public struct MCPServerInfo: Codable {
    /// The server name
    public let name: String
    
    /// The server version
    public let version: String
    
    /// Extra server information as a dictionary
    public let extra: [String: String]
    
    /// Initialize new server information
    /// - Parameters:
    ///   - name: The server name
    ///   - version: The server version
    ///   - extra: Extra server information as a dictionary
    public init(
        name: String,
        version: String,
        extra: [String: String] = [:]
    ) {
        self.name = name
        self.version = version
        self.extra = extra
    }
} 
