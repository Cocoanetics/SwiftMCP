import XCTest
@testable import SwiftMCP

/**
 This test suite verifies that the MCPTool macro correctly handles default values for parameters.
 
 It tests:
 1. Parameters with default values are correctly marked as optional (not required)
 2. Parameters with default values have the correct type in the JSON schema
 3. Multiple parameters with default values in the same function are handled correctly
 
 Note: In the current implementation, the actual default values are not stored in the JSONSchema,
 only the fact that a parameter has a default value (by marking it as not required).
 */
final class MCPToolDefaultValueTests: XCTestCase {
    
    // MARK: - Test Classes
    
    // Test class with functions that have parameters with default values
    @MCPServer
    class DefaultValueFunctions {
        /// Function with integer default value
        /// - Parameter a: First number
        /// - Parameter b: Second number with default value
        @MCPTool
        func intDefault(a: Int, b: Int = 42) -> Int {
            return a + b
        }
        
        /// Function with string default value
        /// - Parameter name: Name with default value
        @MCPTool
        func stringDefault(name: String = "John Doe") -> String {
            return "Hello, \(name)!"
        }
        
        /// Function with boolean default value
        /// - Parameter flag: Boolean flag with default value
        @MCPTool
        func boolDefault(flag: Bool = true) -> Bool {
            return !flag
        }
        
        /// Function with double default value
        /// - Parameter value: Double value with default value
        @MCPTool
        func doubleDefault(value: Double = 3.14) -> Double {
            return value * 2
        }
        
        /// Function with array default value
        /// - Parameter values: Array with default value
        @MCPTool
        func arrayDefault(values: [Int] = [1, 2, 3]) -> Int {
            return values.reduce(0, +)
        }
        
        /// Function with multiple parameters with default values
        /// - Parameter a: First parameter
        /// - Parameter b: Second parameter with default value
        /// - Parameter c: Third parameter with default value
        @MCPTool
        func multipleDefaults(a: String, b: Int = 10, c: Bool = false) -> String {
            return "\(a), \(b), \(c)"
        }
    }
    
    // MARK: - Tests
    
    func testIntDefaultValue() {
        let instance = DefaultValueFunctions()
        let tools = instance.mcpTools
        
        if let intDefaultTool = tools.first(where: { $0.name == "intDefault" }) {
            if case .object(let properties, let required, _) = intDefaultTool.inputSchema {
                // Check default values
                if case .number = properties["a"] {
                    // Parameter 'a' should not have a default value
                } else {
                    XCTFail("Expected number schema for parameter 'a'")
                }
                
                if case .number = properties["b"] {
                    // Parameter 'b' should have a default value of 42
                    // Note: In the current implementation, default values are not stored in the JSONSchema
                } else {
                    XCTFail("Expected number schema for parameter 'b'")
                }
                
                // Check that only 'a' is required since 'b' has a default value
                XCTAssertTrue(required.contains("a"))
                XCTAssertFalse(required.contains("b"))
            } else {
                XCTFail("Expected object schema")
            }
        } else {
            XCTFail("Could not find intDefault function")
        }
    }
    
    func testStringDefaultValue() {
        let instance = DefaultValueFunctions()
        let tools = instance.mcpTools
        
        if let stringDefaultTool = tools.first(where: { $0.name == "stringDefault" }) {
            if case .object(let properties, let required, _) = stringDefaultTool.inputSchema {
                if case .string = properties["name"] {
                    // Parameter 'name' should have a default value of "John Doe"
                    // Note: In the current implementation, default values are not stored in the JSONSchema
                } else {
                    XCTFail("Expected string schema for parameter 'name'")
                }
                
                // Check that 'name' is not required since it has a default value
                XCTAssertFalse(required.contains("name"))
            } else {
                XCTFail("Expected object schema")
            }
        } else {
            XCTFail("Could not find stringDefault function")
        }
    }
    
    func testBoolDefaultValue() {
        let instance = DefaultValueFunctions()
        let tools = instance.mcpTools
        
        if let boolDefaultTool = tools.first(where: { $0.name == "boolDefault" }) {
            if case .object(let properties, let required, _) = boolDefaultTool.inputSchema {
                if case .boolean = properties["flag"] {
                    // Parameter 'flag' should have a default value of true
                    // Note: In the current implementation, default values are not stored in the JSONSchema
                } else {
                    XCTFail("Expected boolean schema for parameter 'flag'")
                }
                
                // Check that 'flag' is not required since it has a default value
                XCTAssertFalse(required.contains("flag"))
            } else {
                XCTFail("Expected object schema")
            }
        } else {
            XCTFail("Could not find boolDefault function")
        }
    }
    
    func testDoubleDefaultValue() {
        let instance = DefaultValueFunctions()
        let tools = instance.mcpTools
        
        if let doubleDefaultTool = tools.first(where: { $0.name == "doubleDefault" }) {
            if case .object(let properties, let required, _) = doubleDefaultTool.inputSchema {
                if case .number = properties["value"] {
                    // Parameter 'value' should have a default value of 3.14
                    // Note: In the current implementation, default values are not stored in the JSONSchema
                } else {
                    XCTFail("Expected number schema for parameter 'value'")
                }
                
                // Check that 'value' is not required since it has a default value
                XCTAssertFalse(required.contains("value"))
            } else {
                XCTFail("Expected object schema")
            }
        } else {
            XCTFail("Could not find doubleDefault function")
        }
    }
    
    func testArrayDefaultValue() {
        let instance = DefaultValueFunctions()
        let tools = instance.mcpTools
        
        if let arrayDefaultTool = tools.first(where: { $0.name == "arrayDefault" }) {
            if case .object(let properties, let required, _) = arrayDefaultTool.inputSchema {
                if case .array = properties["values"] {
                    // Parameter 'values' should have a default value of [1, 2, 3]
                    // Note: In the current implementation, default values are not stored in the JSONSchema
                } else {
                    XCTFail("Expected array schema for parameter 'values'")
                }
                
                // Check that 'values' is not required since it has a default value
                XCTAssertFalse(required.contains("values"))
            } else {
                XCTFail("Expected object schema")
            }
        } else {
            XCTFail("Could not find arrayDefault function")
        }
    }
    
    func testMultipleDefaultValues() {
        let instance = DefaultValueFunctions()
        let tools = instance.mcpTools
        
        if let multipleDefaultsTool = tools.first(where: { $0.name == "multipleDefaults" }) {
            if case .object(let properties, let required, _) = multipleDefaultsTool.inputSchema {
                if case .string = properties["a"] {
                    // Parameter 'a' should not have a default value
                } else {
                    XCTFail("Expected string schema for parameter 'a'")
                }
                
                if case .number = properties["b"] {
                    // Parameter 'b' should have a default value of 10
                    // Note: In the current implementation, default values are not stored in the JSONSchema
                } else {
                    XCTFail("Expected number schema for parameter 'b'")
                }
                
                if case .boolean = properties["c"] {
                    // Parameter 'c' should have a default value of false
                    // Note: In the current implementation, default values are not stored in the JSONSchema
                } else {
                    XCTFail("Expected boolean schema for parameter 'c'")
                }
                
                // Check that only 'a' is required since 'b' and 'c' have default values
                XCTAssertTrue(required.contains("a"))
                XCTAssertFalse(required.contains("b"))
                XCTAssertFalse(required.contains("c"))
            } else {
                XCTFail("Expected object schema")
            }
        } else {
            XCTFail("Could not find multipleDefaults function")
        }
    }
} 
