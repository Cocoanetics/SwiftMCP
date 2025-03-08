import XCTest
@testable import SwiftMCP

final class MCPFunctionWarningTests: XCTestCase {
    
    // MARK: - Test Classes
    
    // Test class with functions missing descriptions
    @MCPTool
    class MissingDescriptions {
        
        // Has documentation but no description line
        /// - Parameter a: A parameter
        @MCPFunction
        func missingDescription(a: Int) {}
        
        // Has description parameter
        @MCPFunction(description: "This function has a description parameter")
        func hasDescriptionParameter() {}
        
        // Has documentation comment with description
        /// This function has a documentation comment
        @MCPFunction
        func hasDocumentationComment() {}
    }
    
    // MARK: - Tests
    
    func testMissingDescriptions() {
        let instance = MissingDescriptions()
        let tools = instance.mcpTools
        
        // Test function with parameter documentation but no function description
        if let missingDescriptionTool = tools.first(where: { $0.name == "missingDescription" }) {
            XCTAssertNotNil(missingDescriptionTool.description, "Function with no description should have nil description")
            
            // Extract properties from the object schema
            if case .object(let properties, _, _) = missingDescriptionTool.inputSchema {
                if case .string(let description) = properties["a"] {
                    XCTAssertEqual(description, "A parameter")
                } else {
                    XCTFail("Expected string schema for parameter 'a'")
                }
            } else {
                XCTFail("Expected object schema")
            }
        } else {
            XCTFail("Could not find missingDescription function")
        }
        
        // Test function with description parameter
        if let hasDescriptionParameterTool = tools.first(where: { $0.name == "hasDescriptionParameter" }) {
            XCTAssertEqual(hasDescriptionParameterTool.description, "This function has a description parameter")
        } else {
            XCTFail("Could not find hasDescriptionParameter function")
        }
        
        // Test function with documentation comment
        if let hasDocumentationCommentTool = tools.first(where: { $0.name == "hasDocumentationComment" }) {
            XCTAssertEqual(hasDocumentationCommentTool.description, "This function has a documentation comment")
        } else {
            XCTFail("Could not find hasDocumentationComment function")
        }
    }
} 
