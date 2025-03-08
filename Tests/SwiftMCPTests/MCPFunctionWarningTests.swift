import XCTest
@testable import SwiftMCP

final class MCPFunctionWarningTests: XCTestCase {
    
    // MARK: - Test Classes
    
    // Test class with functions missing descriptions
    @MCPTool
    class MissingDescriptions {
        // No documentation comment or description parameter
        // This function is intentionally missing a description for testing purposes
        @MCPFunction
        func missingBoth() {}
        
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
        
        // Test function with no description at all
        if let missingBothTool = tools.first(where: { $0.name == "missingBoth" }) {
            XCTAssertNil(missingBothTool.description, "Function with no description should have nil description")
        } else {
            XCTFail("Could not find missingBoth function")
        }
        
        // Test function with parameter documentation but no function description
        if let missingDescriptionTool = tools.first(where: { $0.name == "missingDescription" }) {
            XCTAssertNil(missingDescriptionTool.description, "Function with no description should have nil description")
            XCTAssertEqual(missingDescriptionTool.inputSchema.properties?["a"]?.description, "A parameter")
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