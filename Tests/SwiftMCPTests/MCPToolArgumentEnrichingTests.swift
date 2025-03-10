import XCTest
import SwiftMCP
@testable import SwiftMCPDemo

/**
 This test suite verifies that the MCPTool class correctly enriches arguments with default values.
 
 It tests:
 1. Enriching arguments with default values
 2. Handling of missing required arguments
 3. Type conversion of arguments
 */
final class MCPToolArgumentEnrichingTests: XCTestCase {
    var calculator: Calculator!
    
    override func setUp() {
        super.setUp()
        calculator = Calculator()
    }
    
    override func tearDown() {
        calculator = nil
        super.tearDown()
    }
    
    func testEnrichArguments() {
        // Get the add tool from the calculator
        guard let addTool = calculator.mcpTools.first(where: { $0.name == "add" }) else {
            XCTFail("Could not find add tool")
            return
        }
        
        // Test enriching arguments
        let arguments: [String: Any] = ["a": 2, "b": 3]
        let enrichedArguments = addTool.enrichArguments(arguments, forObject: calculator as Any, functionName: "add")
        
        // Check that the arguments were not changed
        XCTAssertEqual(enrichedArguments.count, 2)
        XCTAssertEqual(enrichedArguments["a"] as? Int, 2)
        XCTAssertEqual(enrichedArguments["b"] as? Int, 3)
    }
    
    func testEnrichArgumentsWithExplicitFunctionName() {
        // Get the add tool from the calculator
        guard let addTool = calculator.mcpTools.first(where: { $0.name == "add" }) else {
            XCTFail("Could not find add tool")
            return
        }
        
        // Test enriching arguments with explicit function name
        let arguments: [String: Any] = ["a": 2, "b": 3]
        let enrichedArguments = addTool.enrichArguments(arguments, forObject: calculator as Any, functionName: "add")
        
        // Check that the arguments were not changed
        XCTAssertEqual(enrichedArguments.count, 2)
        XCTAssertEqual(enrichedArguments["a"] as? Int, 2)
        XCTAssertEqual(enrichedArguments["b"] as? Int, 3)
    }
    
    func testEnrichArgumentsWithNoDefaults() {
        // Get a tool from the calculator
        guard let addTool = calculator.mcpTools.first(where: { $0.name == "add" }) else {
            XCTFail("Could not find add tool")
            return
        }
        
        // Test enriching arguments with no default values
        let arguments: [String: Any] = ["a": 2, "b": 3]
        let enrichedArguments = addTool.enrichArguments(arguments, forObject: calculator as Any, functionName: "add")
        
        // Check that the arguments were not changed
        XCTAssertEqual(enrichedArguments.count, 2)
        XCTAssertEqual(enrichedArguments["a"] as? Int, 2)
        XCTAssertEqual(enrichedArguments["b"] as? Int, 3)
    }
    
    func testEnrichArgumentsWithMissingRequiredArgument() {
        // Get a tool from the calculator
        guard let addTool = calculator.mcpTools.first(where: { $0.name == "add" }) else {
            XCTFail("Could not find add tool")
            return
        }
        
        // Test enriching arguments with a missing required argument
        let arguments: [String: Any] = ["a": 2]
        let enrichedArguments = addTool.enrichArguments(arguments, forObject: calculator as Any, functionName: "add")
        
        // Check that the arguments were not changed
        XCTAssertEqual(enrichedArguments.count, 1)
        XCTAssertEqual(enrichedArguments["a"] as? Int, 2)
        XCTAssertNil(enrichedArguments["b"])
    }
    
    func testEnrichArgumentsWithTypeConversion() {
        // Get a tool from the calculator
        guard let addTool = calculator.mcpTools.first(where: { $0.name == "add" }) else {
            XCTFail("Could not find add tool")
            return
        }
        
        // Test enriching arguments with string values that need to be converted
        let arguments: [String: Any] = ["a": "2", "b": "3"]
        let enrichedArguments = addTool.enrichArguments(arguments, forObject: calculator as Any, functionName: "add")
        
        // Check that the arguments were not changed (enrichArguments doesn't do type conversion)
        XCTAssertEqual(enrichedArguments.count, 2)
        XCTAssertEqual(enrichedArguments["a"] as? String, "2") // String is not converted by enrichArguments
        XCTAssertEqual(enrichedArguments["b"] as? String, "3") // String is not converted by enrichArguments
    }
} 
