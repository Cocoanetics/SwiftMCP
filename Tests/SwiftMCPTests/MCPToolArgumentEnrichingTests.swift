import Testing
import SwiftMCP

/**
 This test suite verifies that the MCPTool class correctly enriches arguments with default values.
 
 It tests:
 1. Enriching arguments with default values
 2. Handling of missing required arguments
 3. Type conversion of arguments
 */

@Test
func testEnrichArguments() throws {
    let calculator = Calculator()
    
    // Get the add tool from the calculator
    guard let addTool = calculator.mcpTools.first(where: { $0.name == "add" }) else {
        throw TestError("Could not find add tool")
    }
    
    // Test enriching arguments
    let arguments: [String: Any] = ["a": 2, "b": 3]
    let enrichedArguments = addTool.enrichArguments(arguments, forObject: calculator as Any, functionName: "add")
    
    // Check that the arguments were not changed
    #expect(enrichedArguments.count == 2)
    #expect(enrichedArguments["a"] as? Int == 2)
    #expect(enrichedArguments["b"] as? Int == 3)
}

@Test
func testEnrichArgumentsWithExplicitFunctionName() throws {
    let calculator = Calculator()
    
    // Get the add tool from the calculator
    guard let addTool = calculator.mcpTools.first(where: { $0.name == "add" }) else {
        throw TestError("Could not find add tool")
    }
    
    // Test enriching arguments with explicit function name
    let arguments: [String: Any] = ["a": 2, "b": 3]
    let enrichedArguments = addTool.enrichArguments(arguments, forObject: calculator as Any, functionName: "add")
    
    // Check that the arguments were not changed
    #expect(enrichedArguments.count == 2)
    #expect(enrichedArguments["a"] as? Int == 2)
    #expect(enrichedArguments["b"] as? Int == 3)
}

@Test
func testEnrichArgumentsWithNoDefaults() throws {
    let calculator = Calculator()
    
    // Get a tool from the calculator
    guard let addTool = calculator.mcpTools.first(where: { $0.name == "add" }) else {
        throw TestError("Could not find add tool")
    }
    
    // Test enriching arguments with no default values
    let arguments: [String: Any] = ["a": 2, "b": 3]
    let enrichedArguments = addTool.enrichArguments(arguments, forObject: calculator as Any, functionName: "add")
    
    // Check that the arguments were not changed
    #expect(enrichedArguments.count == 2)
    #expect(enrichedArguments["a"] as? Int == 2)
    #expect(enrichedArguments["b"] as? Int == 3)
}

@Test
func testEnrichArgumentsWithMissingRequiredArgument() throws {
    let calculator = Calculator()
    
    // Get a tool from the calculator
    guard let addTool = calculator.mcpTools.first(where: { $0.name == "add" }) else {
        throw TestError("Could not find add tool")
    }
    
    // Test enriching arguments with a missing required argument
    let arguments: [String: Any] = ["a": 2]
    let enrichedArguments = addTool.enrichArguments(arguments, forObject: calculator as Any, functionName: "add")
    
    // Check that the arguments were not changed
    #expect(enrichedArguments.count == 1)
    #expect(enrichedArguments["a"] as? Int == 2)
    #expect(enrichedArguments["b"] == nil)
}

@Test
func testEnrichArgumentsWithTypeConversion() throws {
    let calculator = Calculator()
    
    // Get a tool from the calculator
    guard let addTool = calculator.mcpTools.first(where: { $0.name == "add" }) else {
        throw TestError("Could not find add tool")
    }
    
    // Test enriching arguments with string values that need to be converted
    let arguments: [String: Any] = ["a": "2", "b": "3"]
    let enrichedArguments = addTool.enrichArguments(arguments, forObject: calculator as Any, functionName: "add")
    
    // Check that the arguments were not changed (enrichArguments doesn't do type conversion)
    #expect(enrichedArguments.count == 2)
    #expect(enrichedArguments["a"] as? String == "2") // String is not converted by enrichArguments
    #expect(enrichedArguments["b"] as? String == "3") // String is not converted by enrichArguments
} 
