import Testing
import SwiftMCP
import Foundation
import AnyCodable

// Utility function to unwrap optionals in tests
func unwrap<T>(_ optional: T?, message: Comment = "Unexpected nil") -> T {
    #expect(optional != nil, message)
    return optional!
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
