import Testing
@testable import SwiftMCP

/**
 This test suite verifies that the MCPTool macro correctly handles functions with missing descriptions.
 
 It tests:
 1. Functions with parameter documentation but no function description
 2. Functions with an explicit description parameter
 3. Functions with a documentation comment containing a description
 */

// MARK: - Test Classes

// Test class with functions missing descriptions
@MCPServer
class MissingDescriptions {
    
    // Has documentation but no description line
    /// - Parameter a: A parameter
    @MCPTool
    func missingDescription(a: Int) {}
    
    // Has description parameter
    @MCPTool(description: "This function has a description parameter")
    func hasDescriptionParameter() {}
    
    // Has documentation comment with description
    /// This function has a documentation comment
    @MCPTool
    func hasDocumentationComment() {}
}

// MARK: - Tests

@Test
func testMissingDescriptions() throws {
    let instance = MissingDescriptions()
    let tools = instance.mcpTools
    
    // Test function with parameter documentation but no function description
    guard let missingDescriptionTool = tools.first(where: { $0.name == "missingDescription" }) else {
        throw TestError("Could not find missingDescription function")
    }
    
    #expect(missingDescriptionTool.description == nil, "Function with no description should have nil description")
    
    // Extract properties from the object schema
    if case .object(let properties, _, _) = missingDescriptionTool.inputSchema {
        if case .number(let description) = properties["a"] {
            #expect(description == "A parameter")
        } else {
            #expect(Bool(false), "Expected number schema for parameter 'a'")
        }
    } else {
        #expect(Bool(false), "Expected object schema")
    }
    
    // Test function with description parameter
    guard let hasDescriptionParameterTool = tools.first(where: { $0.name == "hasDescriptionParameter" }) else {
        throw TestError("Could not find hasDescriptionParameter function")
    }
    
    #expect(hasDescriptionParameterTool.description == "This function has a description parameter")
    
    // Test function with documentation comment
    guard let hasDocumentationCommentTool = tools.first(where: { $0.name == "hasDocumentationComment" }) else {
        throw TestError("Could not find hasDocumentationComment function")
    }
    
    #expect(hasDocumentationCommentTool.description == "This function has a documentation comment")
}
