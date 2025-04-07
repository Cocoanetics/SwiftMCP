import Testing
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

// MARK: - Test Classes

// Test class with functions that have parameters with default values
@MCPServer
final class DefaultValueFunctions {
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

@Test
func testIntDefaultValue() throws {
    let instance = DefaultValueFunctions()
    let tools = instance.mcpToolMetadata.convertedToTools()
    
    guard let intDefaultTool = tools.first(where: { $0.name == "intDefault" }) else {
        throw TestError("Could not find intDefault function")
    }
    
    if case .object(let properties, let required, _) = intDefaultTool.inputSchema {
        // Check default values
        if case .number = properties["a"] {
            // Parameter 'a' should not have a default value
        } else {
            #expect(Bool(false), "Expected number schema for parameter 'a'")
        }
        
        if case .number = properties["b"] {
            // Parameter 'b' should have a default value of 42
            // Note: In the current implementation, default values are not stored in the JSONSchema
        } else {
            #expect(Bool(false), "Expected number schema for parameter 'b'")
        }
        
        // Check that only 'a' is required since 'b' has a default value
        #expect(required.contains("a"))
        #expect(!required.contains("b"))
    } else {
        #expect(Bool(false), "Expected object schema")
    }
}

@Test
func testStringDefaultValue() throws {
    let instance = DefaultValueFunctions()
    let tools = instance.mcpToolMetadata.convertedToTools()
    
    guard let stringDefaultTool = tools.first(where: { $0.name == "stringDefault" }) else {
        throw TestError("Could not find stringDefault function")
    }
    
    if case .object(let properties, let required, _) = stringDefaultTool.inputSchema {
        if case .string = properties["name"] {
            // Parameter 'name' should have a default value of "John Doe"
            // Note: In the current implementation, default values are not stored in the JSONSchema
        } else {
            #expect(Bool(false), "Expected string schema for parameter 'name'")
        }
        
        // Check that 'name' is not required since it has a default value
        #expect(!required.contains("name"))
    } else {
        #expect(Bool(false), "Expected object schema")
    }
}

@Test
func testBoolDefaultValue() throws {
    let instance = DefaultValueFunctions()
    let tools = instance.mcpToolMetadata.convertedToTools()
    
    guard let boolDefaultTool = tools.first(where: { $0.name == "boolDefault" }) else {
        throw TestError("Could not find boolDefault function")
    }
    
    if case .object(let properties, let required, _) = boolDefaultTool.inputSchema {
        if case .boolean = properties["flag"] {
            // Parameter 'flag' should have a default value of true
            // Note: In the current implementation, default values are not stored in the JSONSchema
        } else {
            #expect(Bool(false), "Expected boolean schema for parameter 'flag'")
        }
        
        // Check that 'flag' is not required since it has a default value
        #expect(!required.contains("flag"))
    } else {
        #expect(Bool(false), "Expected object schema")
    }
}

@Test
func testDoubleDefaultValue() throws {
    let instance = DefaultValueFunctions()
    let tools = instance.mcpToolMetadata.convertedToTools()
    
    guard let doubleDefaultTool = tools.first(where: { $0.name == "doubleDefault" }) else {
        throw TestError("Could not find doubleDefault function")
    }
    
    if case .object(let properties, let required, _) = doubleDefaultTool.inputSchema {
        if case .number = properties["value"] {
            // Parameter 'value' should have a default value of 3.14
            // Note: In the current implementation, default values are not stored in the JSONSchema
        } else {
            #expect(Bool(false), "Expected number schema for parameter 'value'")
        }
        
        // Check that 'value' is not required since it has a default value
        #expect(!required.contains("value"))
    } else {
        #expect(Bool(false), "Expected object schema")
    }
}

@Test
func testArrayDefaultValue() throws {
    let instance = DefaultValueFunctions()
    let tools = instance.mcpToolMetadata.convertedToTools()
    
    guard let arrayDefaultTool = tools.first(where: { $0.name == "arrayDefault" }) else {
        throw TestError("Could not find arrayDefault function")
    }
    
	print(arrayDefaultTool.inputSchema)
	
    if case .object(let properties, let required, _) = arrayDefaultTool.inputSchema {
        if case .array = properties["values"] {
            // Parameter 'values' should have a default value of [1, 2, 3]
            // Note: In the current implementation, default values are not stored in the JSONSchema
        } else {
            #expect(Bool(false), "Expected array schema for parameter 'values'")
        }
        
        // Check that 'values' is not required since it has a default value
        #expect(!required.contains("values"))
    } else {
        #expect(Bool(false), "Expected object schema")
    }
}

@Test
func testMultipleDefaultValues() throws {
    let instance = DefaultValueFunctions()
    let tools = instance.mcpToolMetadata.convertedToTools()
    
    guard let multipleDefaultsTool = tools.first(where: { $0.name == "multipleDefaults" }) else {
        throw TestError("Could not find multipleDefaults function")
    }
    
    if case .object(let properties, let required, _) = multipleDefaultsTool.inputSchema {
        if case .string = properties["a"] {
            // Parameter 'a' should not have a default value
        } else {
            #expect(Bool(false), "Expected string schema for parameter 'a'")
        }
        
        if case .number = properties["b"] {
            // Parameter 'b' should have a default value of 10
            // Note: In the current implementation, default values are not stored in the JSONSchema
        } else {
            #expect(Bool(false), "Expected number schema for parameter 'b'")
        }
        
        if case .boolean = properties["c"] {
            // Parameter 'c' should have a default value of false
            // Note: In the current implementation, default values are not stored in the JSONSchema
        } else {
            #expect(Bool(false), "Expected boolean schema for parameter 'c'")
        }
        
        // Check that only 'a' is required since 'b' and 'c' have default values
        #expect(required.contains("a"))
        #expect(!required.contains("b"))
        #expect(!required.contains("c"))
    } else {
        #expect(Bool(false), "Expected object schema")
    }
} 
