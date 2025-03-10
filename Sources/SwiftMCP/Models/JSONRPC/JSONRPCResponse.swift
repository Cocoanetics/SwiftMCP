import Foundation

// MARK: - JSON-RPC Structures

/// JSON-RPC Response structures
public struct JSONRPCResponse: Codable {
    public var jsonrpc: String = "2.0"
    public let id: Int?
    public let result: ResponseResult
    
    public init(jsonrpc: String = "2.0", id: Int?, result: ResponseResult) {
        self.jsonrpc = jsonrpc
        self.id = id
        self.result = result
    }
    
    public struct ResponseResult: Codable {
        public let protocolVersion: String
        public let capabilities: Capabilities
        public let serverInfo: ServerInfo
        
        public init(protocolVersion: String, capabilities: Capabilities, serverInfo: ServerInfo) {
            self.protocolVersion = protocolVersion
            self.capabilities = capabilities
            self.serverInfo = serverInfo
        }
        
        public struct Capabilities: Codable {
            public var experimental: [String: String]? = [:]
            public let tools: Tools
            
            public init(experimental: [String: String]? = [:], tools: Tools) {
                self.experimental = experimental
                self.tools = tools
            }
            
            public struct Tools: Codable {
                public let listChanged: Bool
                
                public init(listChanged: Bool) {
                    self.listChanged = listChanged
                }
            }
        }
        
        public struct ServerInfo: Codable {
            public let name: String
            public let version: String
            
            public init(name: String, version: String) {
                self.name = name
                self.version = version
            }
        }
    }
} 
