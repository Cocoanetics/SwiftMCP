import XCTest
import SwiftMCP
@testable import SwiftMCPDemo

final class MCPToolTests: XCTestCase {
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
        // Get a tool from the calculator
        guard let divideTool = calculator.mcpTools.first(where: { $0.name == "divide" }) else {
            XCTFail("Could not find divide tool")
            return
        }
        
        // Test enriching arguments with default values
        let arguments: [String: Any] = ["numerator": 10.0]
        let enrichedArguments = divideTool.enrichArguments(arguments, forObject: calculator as Any, functionName: "divide")
        
        // Check that the denominator was added with the default value
        XCTAssertEqual(enrichedArguments.count, 2)
        XCTAssertEqual(enrichedArguments["numerator"] as? Double, 10.0)
        XCTAssertEqual(enrichedArguments["denominator"] as? Double, 1.0)
    }
    
    func testEnrichArgumentsWithExplicitFunctionName() {
        // Get a tool from the calculator
        guard let divideTool = calculator.mcpTools.first(where: { $0.name == "divide" }) else {
            XCTFail("Could not find divide tool")
            return
        }
        
        // Test enriching arguments with default values and explicit function name
        let arguments: [String: Any] = ["numerator": 10.0]
        let enrichedArguments = divideTool.enrichArguments(arguments, forObject: calculator as Any, functionName: "divide")
        
        // Check that the denominator was added with the default value
        XCTAssertEqual(enrichedArguments.count, 2)
        XCTAssertEqual(enrichedArguments["numerator"] as? Double, 10.0)
        XCTAssertEqual(enrichedArguments["denominator"] as? Double, 1.0)
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
        guard let divideTool = calculator.mcpTools.first(where: { $0.name == "divide" }) else {
            XCTFail("Could not find divide tool")
            return
        }
        
        // Test enriching arguments with string values that need to be converted
        let arguments: [String: Any] = ["numerator": "10.0"]
        let enrichedArguments = divideTool.enrichArguments(arguments, forObject: calculator as Any, functionName: "divide")
        
        // Check that the denominator was added with the default value
        XCTAssertEqual(enrichedArguments.count, 2)
        XCTAssertEqual(enrichedArguments["numerator"] as? String, "10.0") // String is not converted by enrichArguments
        XCTAssertEqual(enrichedArguments["denominator"] as? Double, 1.0)
    }
} 