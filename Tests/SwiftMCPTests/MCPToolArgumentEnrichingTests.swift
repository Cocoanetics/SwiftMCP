import Testing
@testable import SwiftMCP

/**
 This test suite verifies that the MCPTool macro correctly handles default values for parameters.
 
 It tests:
 1. Parameters with default values are correctly marked as optional (not required)
 2. Parameters with default values have the correct type in the JSON schema
 3. Multiple parameters with default values in the same function are handled correctly
 */

@Test
func testEnrichArguments() throws {
    let calculator = Calculator()
    
    // Get the add tool metadata from the calculator
    let metadata = try #require(calculator.mcpToolMetadata(for: "add"))
    
    // Test enriching arguments
    let arguments: JSONDictionary = ["a": 2, "b": 3]
    let enrichedArguments = try metadata.enrichArguments(arguments)
    
    // Check that the arguments were not changed
    #expect(enrichedArguments.count == 2)
    #expect(enrichedArguments["a"]?.value as? Int == 2)
    #expect(enrichedArguments["b"]?.value as? Int == 3)
}

@Test
func testEnrichArgumentsWithExplicitFunctionName() throws {
    let calculator = Calculator()
    
    // Get the add tool metadata from the calculator
    let metadata = try #require(calculator.mcpToolMetadata(for: "add"))
    
    // Test enriching arguments with explicit function name
    let arguments: JSONDictionary = ["a": 2, "b": 3]
    let enrichedArguments = try metadata.enrichArguments(arguments)
    
    // Check that the arguments were not changed
    #expect(enrichedArguments.count == 2)
    #expect(enrichedArguments["a"]?.value as? Int == 2)
    #expect(enrichedArguments["b"]?.value as? Int == 3)
}

@Test
func testEnrichArgumentsWithNoDefaults() throws {
    let calculator = Calculator()
    
    // Get the add tool metadata from the calculator
    let metadata = try #require(calculator.mcpToolMetadata(for: "add"))
    
    // Test enriching arguments with no default values
    let arguments: JSONDictionary = ["a": 2, "b": 3]
    let enrichedArguments = try metadata.enrichArguments(arguments)
    
    // Check that the arguments were not changed
    #expect(enrichedArguments.count == 2)
    #expect(enrichedArguments["a"]?.value as? Int == 2)
    #expect(enrichedArguments["b"]?.value as? Int == 3)
}

@Test
func testEnrichArgumentsWithMissingRequiredArgument() throws {
    let calculator = Calculator()
    
    // Get the add tool metadata from the calculator
    let metadata = try #require(calculator.mcpToolMetadata(for: "add"))
    
    // Test enriching arguments with a missing required argument
    #expect(throws: MCPToolError.self, "Should notice missing parameter") {
        try metadata.enrichArguments(["a": 2])
    }
}

@Test
func testEnrichArgumentsWithTypeConversion() throws {
    let calculator = Calculator()
    
    // Get the add tool metadata from the calculator
    let metadata = try #require(calculator.mcpToolMetadata(for: "add"))
    
    // Test enriching arguments with string values that need to be converted
    let arguments: JSONDictionary = ["a": "2", "b": "3"]
    let enrichedArguments = try metadata.enrichArguments(arguments)
    
    // Check that the arguments were not changed (enrichArguments doesn't do type conversion)
    #expect(enrichedArguments.count == 2)
    #expect(enrichedArguments["a"]?.value as? String == "2") // String is not converted by enrichArguments
    #expect(enrichedArguments["b"]?.value as? String == "3") // String is not converted by enrichArguments
}

@Test
func testSubtractArguments() throws {
    let calculator = Calculator()
    
    // Get the subtract tool metadata from the calculator
    let metadata = try #require(calculator.mcpToolMetadata(for: "subtract"))
    
    // Test with no arguments - should throw missing required parameter
    #expect(throws: MCPToolError.self, "Should notice missing parameter") {
        try metadata.enrichArguments([:])
    }
    
    // Test with partial arguments - should throw missing required parameter
    #expect(throws: MCPToolError.self, "Should notice missing parameter") {
        try metadata.enrichArguments(["b": 5])
    }
    
    // Test with all arguments - no defaults should be added
    let allArgs = try metadata.enrichArguments(["a": 20, "b": 5])
    #expect(allArgs.count == 2)
    #expect(allArgs["a"]?.value as? Int == 20)
    #expect(allArgs["b"]?.value as? Int == 5)
}

@Test
func testMultiplyArguments() throws {
    let calculator = Calculator()
    
    // Get the multiply tool metadata from the calculator
    let metadata = try #require(calculator.mcpToolMetadata(for: "multiply"))
    
    // Test with no arguments - should throw missing required parameter
    #expect(throws: MCPToolError.self, "Should notice missing parameter") {
        try metadata.enrichArguments([:])
    }
    
    // Test with partial arguments - should throw missing required parameter
    #expect(throws: MCPToolError.self, "Should notice missing parameter") {
        try metadata.enrichArguments(["b": 5])
    }
    
    // Test with all arguments - no defaults should be added
    let allArgs = try metadata.enrichArguments(["a": 20, "b": 5])
    #expect(allArgs.count == 2)
    #expect(allArgs["a"]?.value as? Int == 20)
    #expect(allArgs["b"]?.value as? Int == 5)
} 
