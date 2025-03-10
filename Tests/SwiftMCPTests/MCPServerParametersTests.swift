import Testing
import SwiftMCP
import Foundation
import AnyCodable

// Utility function to unwrap optionals in tests
func unwrap<T>(_ optional: T?, message: Comment = "Unexpected nil") -> T {
    #expect(optional != nil, message)
    return optional!
}

// We need to modify the MCPServer protocol implementation to expose the server info for testing
extension MCPServer {
    // This function is modified from the default implementation to use our custom name and version
    func createInitializeResponseForTest(id: Int) -> JSONRPC.Response {
        // Access the private variables using Mirror
        let mirror = Mirror(reflecting: self)
        
        // Use nil coalescing with more descriptive default values
        let serverName = mirror.children.first(where: { $0.label == "__mcpServerName" })?.value as? String ?? "UnknownServer"
        let serverVersion = mirror.children.first(where: { $0.label == "__mcpServerVersion" })?.value as? String ?? "UnknownVersion"
        
        let serverInfo = MCPServerInfo(
            name: serverName,
            version: serverVersion
        )
        
        let result = MCPCapabilitiesResult(
            protocol_version: "0.1.0",
            capabilities: MCPCapabilities(tools: mcpTools),
            server_info: serverInfo,
            instructions: "Welcome to SwiftMCP!"
        )
        
        return JSONRPC.Response(id: .number(id), result: .init(result))
    }
}

@MCPServer(name: "CustomCalculator", version: "2.0")
class CustomNameCalculator: MCPServer {
    @MCPTool(description: "Simple addition")
    func add(a: Int, b: Int) -> Int {
        return a + b
    }
}

@MCPServer
class DefaultNameCalculator: MCPServer {
    @MCPTool(description: "Simple addition")
    func add(a: Int, b: Int) -> Int {
        return a + b
    }
}

@Test("Custom Name and Version")
func testCustomNameAndVersion() throws {
    // Create an instance of CustomNameCalculator
    let calculator = CustomNameCalculator()
    
    // Get the response using our test method
    let response = calculator.createInitializeResponseForTest(id: 1)
    
    // Extract server info from the response using our unwrap function
    let capabilitiesResult = unwrap(response.result?.value as? MCPCapabilitiesResult, 
                                   message: "Failed to extract capabilities result from response")
    let serverInfo = capabilitiesResult.server_info
    
    #expect(serverInfo.name == "CustomCalculator", "Server name should match specified name")
    #expect(serverInfo.version == "2.0", "Server version should match specified version")
}

@Test("Default Name and Version")
func testDefaultNameAndVersion() throws {
    // Create an instance of DefaultNameCalculator
    let calculator = DefaultNameCalculator()
    
    // Get the response using our test method
    let response = calculator.createInitializeResponseForTest(id: 1)
    
    // Extract server info from the response using our unwrap function
    let capabilitiesResult = unwrap(response.result?.value as? MCPCapabilitiesResult,
                                   message: "Failed to extract capabilities result from response")
    let serverInfo = capabilitiesResult.server_info
    
    #expect(serverInfo.name == "DefaultNameCalculator", "Server name should match class name")
    #expect(serverInfo.version == "1.0", "Server version should be default value")
}
