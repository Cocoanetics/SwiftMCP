import XCTest
@testable import SwiftMCP

final class MCPFunctionDefaultValueTests: XCTestCase {
    
    // MARK: - Test Classes
    
    // Test class with functions that have parameters with default values
    @MCPTool
    class DefaultValueFunctions {
        /// Function with integer default value
        /// - Parameter a: First number
        /// - Parameter b: Second number with default value
        @MCPFunction
        func intDefault(a: Int, b: Int = 42) -> Int {
            return a + b
        }
        
        /// Function with string default value
        /// - Parameter name: Name with default value
        @MCPFunction
        func stringDefault(name: String = "John Doe") -> String {
            return "Hello, \(name)!"
        }
        
        /// Function with boolean default value
        /// - Parameter flag: Boolean flag with default value
        @MCPFunction
        func boolDefault(flag: Bool = true) -> Bool {
            return !flag
        }
        
        /// Function with double default value
        /// - Parameter value: Double value with default value
        @MCPFunction
        func doubleDefault(value: Double = 3.14) -> Double {
            return value * 2
        }
        
        /// Function with array default value
        /// - Parameter values: Array with default value
        @MCPFunction
        func arrayDefault(values: [Int] = [1, 2, 3]) -> Int {
            return values.reduce(0, +)
        }
        
        /// Function with multiple parameters with default values
        /// - Parameter a: First parameter
        /// - Parameter b: Second parameter with default value
        /// - Parameter c: Third parameter with default value
        @MCPFunction
        func multipleDefaults(a: String, b: Int = 10, c: Bool = false) -> String {
            return "\(a), \(b), \(c)"
        }
    }
    
    // MARK: - Tests
    
    func testIntDefaultValue() {
        let instance = DefaultValueFunctions()
        let tools = instance.mcpTools
        
        if let intDefaultTool = tools.first(where: { $0.name == "intDefault" }) {
            XCTAssertEqual(intDefaultTool.inputSchema.properties?["a"]?.defaultValue, nil)
            XCTAssertEqual(intDefaultTool.inputSchema.properties?["b"]?.defaultValue, "42")
            
            // Check that only 'a' is required since 'b' has a default value
            XCTAssertTrue(intDefaultTool.inputSchema.required?.contains("a") ?? false)
            XCTAssertFalse(intDefaultTool.inputSchema.required?.contains("b") ?? true)
        } else {
            XCTFail("Could not find intDefault function")
        }
    }
    
    func testStringDefaultValue() {
        let instance = DefaultValueFunctions()
        let tools = instance.mcpTools
        
        if let stringDefaultTool = tools.first(where: { $0.name == "stringDefault" }) {
            print("String default value: \(String(describing: stringDefaultTool.inputSchema.properties?["name"]?.defaultValue))")
            print("Required parameters: \(String(describing: stringDefaultTool.inputSchema.required))")
            
            XCTAssertEqual(stringDefaultTool.inputSchema.properties?["name"]?.defaultValue, "\"John Doe\"")
            
            // Check that 'name' is not required since it has a default value
            XCTAssertFalse(stringDefaultTool.inputSchema.required?.contains("name") ?? true)
        } else {
            XCTFail("Could not find stringDefault function")
        }
    }
    
    func testBoolDefaultValue() {
        let instance = DefaultValueFunctions()
        let tools = instance.mcpTools
        
        if let boolDefaultTool = tools.first(where: { $0.name == "boolDefault" }) {
            XCTAssertEqual(boolDefaultTool.inputSchema.properties?["flag"]?.defaultValue, "true")
            
            // Check that 'flag' is not required since it has a default value
            XCTAssertFalse(boolDefaultTool.inputSchema.required?.contains("flag") ?? true)
        } else {
            XCTFail("Could not find boolDefault function")
        }
    }
    
    func testDoubleDefaultValue() {
        let instance = DefaultValueFunctions()
        let tools = instance.mcpTools
        
        if let doubleDefaultTool = tools.first(where: { $0.name == "doubleDefault" }) {
            XCTAssertEqual(doubleDefaultTool.inputSchema.properties?["value"]?.defaultValue, "3.14")
            
            // Check that 'value' is not required since it has a default value
            XCTAssertFalse(doubleDefaultTool.inputSchema.required?.contains("value") ?? true)
        } else {
            XCTFail("Could not find doubleDefault function")
        }
    }
    
    func testArrayDefaultValue() {
        let instance = DefaultValueFunctions()
        let tools = instance.mcpTools
        
        if let arrayDefaultTool = tools.first(where: { $0.name == "arrayDefault" }) {
            // The array default value might be represented differently depending on the implementation
            XCTAssertNotNil(arrayDefaultTool.inputSchema.properties?["values"]?.defaultValue)
            
            // Check that 'values' is not required since it has a default value
            XCTAssertFalse(arrayDefaultTool.inputSchema.required?.contains("values") ?? true)
        } else {
            XCTFail("Could not find arrayDefault function")
        }
    }
    
    func testMultipleDefaultValues() {
        let instance = DefaultValueFunctions()
        let tools = instance.mcpTools
        
        if let multipleDefaultsTool = tools.first(where: { $0.name == "multipleDefaults" }) {
            XCTAssertEqual(multipleDefaultsTool.inputSchema.properties?["a"]?.defaultValue, nil)
            XCTAssertEqual(multipleDefaultsTool.inputSchema.properties?["b"]?.defaultValue, "10")
            XCTAssertEqual(multipleDefaultsTool.inputSchema.properties?["c"]?.defaultValue, "false")
            
            // Check that only 'a' is required since 'b' and 'c' have default values
            XCTAssertTrue(multipleDefaultsTool.inputSchema.required?.contains("a") ?? false)
            XCTAssertFalse(multipleDefaultsTool.inputSchema.required?.contains("b") ?? true)
            XCTAssertFalse(multipleDefaultsTool.inputSchema.required?.contains("c") ?? true)
        } else {
            XCTFail("Could not find multipleDefaults function")
        }
    }
} 