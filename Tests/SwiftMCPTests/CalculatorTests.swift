import XCTest
import SwiftMCP

final class CalculatorTests: XCTestCase {
    var calculator: Calculator!
    
    override func setUp() {
        super.setUp()
        calculator = Calculator()
    }
    
    override func tearDown() {
        calculator = nil
        super.tearDown()
    }
    
    func testAdd() throws {
        // Test direct function call
        XCTAssertEqual(calculator.add(a: 2, b: 3), 5)
        
        // Test through callTool
        let result = try calculator.callTool("add", arguments: ["a": 2, "b": 3])
        XCTAssertEqual(result as? Int, 5)
    }
    
    func testTestArray() throws {
        // Test direct function call
        XCTAssertEqual(calculator.testArray(a: [1, 2, 3]), "1, 2, 3")
        
        // Test through callTool
        let result = try calculator.callTool("testArray", arguments: ["a": [1, 2, 3]])
        XCTAssertEqual(result as? String, "1, 2, 3")
    }
    
    func testUnknownTool() {
        XCTAssertThrowsError(try calculator.callTool("unknown", arguments: [:]), "Should throw an error for unknown tool") { error in
            guard let mcpError = error as? MCPToolError else {
                XCTFail("Error should be MCPToolError")
                return
            }
            
            if case .unknownTool(let name) = mcpError {
                XCTAssertEqual(name, "unknown")
            } else {
                XCTFail("Error should be unknownTool")
            }
        }
    }
    
    func testInvalidArgumentType() {
        XCTAssertThrowsError(try calculator.callTool("add", arguments: ["a": "not_a_number", "b": 3]), "Should throw an error for invalid argument type") { error in
            guard let mcpError = error as? MCPToolError else {
                XCTFail("Error should be MCPToolError")
                return
            }
            
            if case .invalidArgumentType(let name, let parameterName, let expectedType, _) = mcpError {
                XCTAssertEqual(name, "add")
                XCTAssertEqual(parameterName, "a")
                XCTAssertEqual(expectedType, "Int")
            } else {
                XCTFail("Error should be invalidArgumentType")
            }
        }
    }
} 
