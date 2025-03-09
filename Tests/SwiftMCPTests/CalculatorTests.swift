import XCTest
import SwiftMCP
@testable import SwiftMCPDemo

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
    
    func testSubtract() throws {
        // Test direct function call
        XCTAssertEqual(calculator.subtract(a: 5, b: 2), 3)
        
        // Test through callTool
        let result = try calculator.callTool("subtract", arguments: ["a": 5, "b": 2])
        XCTAssertEqual(result as? Int, 3)
        
        // Test with default value
        let resultWithDefault = try calculator.callTool("subtract", arguments: ["a": 5])
        XCTAssertEqual(resultWithDefault as? Int, 2) // 5 - 3 (default value)
    }
    
    func testMultiply() throws {
        // Test direct function call
        XCTAssertEqual(calculator.multiply(a: 4, b: 6), 24)
        
        // Test through callTool
        let result = try calculator.callTool("multiply", arguments: ["a": 4, "b": 6])
        XCTAssertEqual(result as? Int, 24)
    }
    
    func testDivide() throws {
        // Test direct function call
        XCTAssertEqual(calculator.divide(numerator: 10, denominator: 2), 5.0)
        
        // Test through callTool
        let result = try calculator.callTool("divide", arguments: ["numerator": 10.0, "denominator": 2.0])
        XCTAssertEqual(result as? Double, 5.0)
        
        // Test with default value
        let resultWithDefault = try calculator.callTool("divide", arguments: ["numerator": 10.0])
        XCTAssertEqual(resultWithDefault as? Double, 10.0) // 10 / 1 (default value)
    }
    
    func testGreet() throws {
        // Test direct function call
        XCTAssertEqual(calculator.greet(name: "Swift"), "Hello, Swift!")
        
        // Test through callTool
        let result = try calculator.callTool("greet", arguments: ["name": "Swift"])
        XCTAssertEqual(result as? String, "Hello, Swift!")
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
        XCTAssertThrowsError(try calculator.callTool("divide", arguments: ["numerator": "not_a_number"]), "Should throw an error for invalid argument type") { error in
            guard let mcpError = error as? MCPToolError else {
                XCTFail("Error should be MCPToolError")
                return
            }
            
            if case .invalidArgumentType(let name, let parameterName, let expectedType, _) = mcpError {
                XCTAssertEqual(name, "divide")
                XCTAssertEqual(parameterName, "numerator")
                XCTAssertEqual(expectedType, "Double")
            } else {
                XCTFail("Error should be invalidArgumentType")
            }
        }
    }
} 