import XCTest
@testable import SwiftMCP

final class MCPFunctionTests: XCTestCase {
    
    // MARK: - Test Classes
    
    // Test class with triple-slash documentation
    @MCPTool
    class TripleSlashDocumentation {
        /// Simple function with no parameters
        /// - Returns: A string
        @MCPFunction
        func noParameters() -> String {
            return "No parameters"
        }
        
        /// Function with basic parameter types
        /// - Parameter a: An integer parameter
        /// - Parameter b: A string parameter
        /// - Parameter c: A boolean parameter
        /// - Returns: A string description
        @MCPFunction
        func basicTypes(a: Int, b: String, c: Bool) -> String {
            return "Basic types: \(a), \(b), \(c)"
        }
        
        /// Function with complex parameter types
        /// - Parameter array: An array of integers
        /// - Parameter dictionary: A dictionary with string keys and any values
        /// - Parameter closure: A closure that takes an integer and returns a string
        @MCPFunction
        func complexTypes(
            array: [Int],
            dictionary: [String: Any],
            closure: (Int) -> String
        ) {
            // Implementation not important for the test
        }
        
        /// Function with explicit description override
        /// - Parameter value: A value with description
        @MCPFunction(description: "This description overrides the documentation comment")
        func explicitDescription(value: Double) -> Double {
            return value * 2
        }
        
        /// Function with optional parameters
        /// - Parameter required: A required parameter
        /// - Parameter optional: An optional parameter
        @MCPFunction
        func optionalParameter(required: String, optional: Int? = nil) {
            // Implementation not important for the test
        }
    }
    
    // Test class with multi-line documentation
    @MCPTool
    class MultiLineDocumentation {
        /**
         Function with multi-line documentation
         - Parameter a: First parameter
         - Parameter b: Second parameter
         */
        @MCPFunction
        func multiLineDoc(a: Int, b: Int) -> Int {
            return a + b
        }
        
        /**
         This function has a very long description that spans
         multiple lines to test how the macro handles multi-line
         documentation comments.
         - Parameter text: A text parameter with a long description
                          that also spans multiple lines to test
                          how parameter descriptions are extracted
         */
        @MCPFunction
        func longDescription(text: String) {
            // Implementation not important for the test
        }
    }
    
    // Test class with mixed documentation styles
    @MCPTool
    class MixedDocumentationStyles {
        /// Triple-slash documentation
        @MCPFunction
        func tripleSlash() {}
        
        /** Multi-line documentation */
        @MCPFunction
        func multiLine() {}
        
        // Regular comment (should not be extracted)
        @MCPFunction(description: "Explicit description needed")
        func regularComment() {}
    }
    
    // MARK: - Tests
    
    func testTripleSlashDocumentation() {
        let instance = TripleSlashDocumentation()
        let tools = instance.mcpTools
        
        // Test function with no parameters
        if let noParamsTool = tools.first(where: { $0.name == "noParameters" }) {
            XCTAssertEqual(noParamsTool.description, "Simple function with no parameters")
            XCTAssertTrue(noParamsTool.inputSchema.properties?.isEmpty ?? true)
        } else {
            XCTFail("Could not find noParameters function")
        }
        
        // Test function with basic parameter types
        if let basicTypesTool = tools.first(where: { $0.name == "basicTypes" }) {
            XCTAssertEqual(basicTypesTool.description, "Function with basic parameter types")
            XCTAssertEqual(basicTypesTool.inputSchema.properties?.count, 3)
            
            // Check parameter descriptions
            XCTAssertEqual(basicTypesTool.inputSchema.properties?["a"]?.description, "An integer parameter")
            XCTAssertEqual(basicTypesTool.inputSchema.properties?["b"]?.description, "A string parameter")
            XCTAssertEqual(basicTypesTool.inputSchema.properties?["c"]?.description, "A boolean parameter")
            
            // Check parameter types
            XCTAssertEqual(basicTypesTool.inputSchema.properties?["a"]?.type, "number")
            XCTAssertEqual(basicTypesTool.inputSchema.properties?["b"]?.type, "string")
            XCTAssertEqual(basicTypesTool.inputSchema.properties?["c"]?.type, "boolean")
        } else {
            XCTFail("Could not find basicTypes function")
        }
        
        // Test function with complex parameter types
        if let complexTypesTool = tools.first(where: { $0.name == "complexTypes" }) {
            XCTAssertEqual(complexTypesTool.description, "Function with complex parameter types")
            XCTAssertEqual(complexTypesTool.inputSchema.properties?.count, 3)
            
            // Check parameter descriptions
            XCTAssertEqual(complexTypesTool.inputSchema.properties?["array"]?.description, "An array of integers")
            XCTAssertEqual(complexTypesTool.inputSchema.properties?["dictionary"]?.description, "A dictionary with string keys and any values")
            XCTAssertEqual(complexTypesTool.inputSchema.properties?["closure"]?.description, "A closure that takes an integer and returns a string")
            
            // Check array parameter type
            XCTAssertEqual(complexTypesTool.inputSchema.properties?["array"]?.type, "array")
            XCTAssertEqual(complexTypesTool.inputSchema.properties?["array"]?.items?.type, "number")
        } else {
            XCTFail("Could not find complexTypes function")
        }
        
        // Test function with explicit description override
        if let explicitDescTool = tools.first(where: { $0.name == "explicitDescription" }) {
            XCTAssertEqual(explicitDescTool.description, "This description overrides the documentation comment")
            XCTAssertEqual(explicitDescTool.inputSchema.properties?["value"]?.description, "A value with description")
        } else {
            XCTFail("Could not find explicitDescription function")
        }
        
        // Test function with optional parameters
        if let optionalParamTool = tools.first(where: { $0.name == "optionalParameter" }) {
            XCTAssertEqual(optionalParamTool.description, "Function with optional parameters")
            XCTAssertEqual(optionalParamTool.inputSchema.properties?["required"]?.description, "A required parameter")
            XCTAssertEqual(optionalParamTool.inputSchema.properties?["optional"]?.description, "An optional parameter")
        } else {
            XCTFail("Could not find optionalParameter function")
        }
    }
    
    func testMultiLineDocumentation() {
        let instance = MultiLineDocumentation()
        let tools = instance.mcpTools
        
        // Test function with multi-line documentation
        if let multiLineDocTool = tools.first(where: { $0.name == "multiLineDoc" }) {
            XCTAssertEqual(multiLineDocTool.description, "Function with multi-line documentation")
            XCTAssertEqual(multiLineDocTool.inputSchema.properties?["a"]?.description, "First parameter")
            XCTAssertEqual(multiLineDocTool.inputSchema.properties?["b"]?.description, "Second parameter")
        } else {
            XCTFail("Could not find multiLineDoc function")
        }
        
        // Test function with long description
        if let longDescTool = tools.first(where: { $0.name == "longDescription" }) {
            XCTAssertTrue(longDescTool.description?.contains("This function has a very long description") ?? false)
            XCTAssertTrue(longDescTool.inputSchema.properties?["text"]?.description?.contains("A text parameter with a long description") ?? false)
        } else {
            XCTFail("Could not find longDescription function")
        }
    }
    
    func testMixedDocumentationStyles() {
        let instance = MixedDocumentationStyles()
        let tools = instance.mcpTools
        
        // Test triple-slash documentation
        if let tripleSlashTool = tools.first(where: { $0.name == "tripleSlash" }) {
            XCTAssertEqual(tripleSlashTool.description, "Triple-slash documentation")
        } else {
            XCTFail("Could not find tripleSlash function")
        }
        
        // Test multi-line documentation
        if let multiLineTool = tools.first(where: { $0.name == "multiLine" }) {
            XCTAssertEqual(multiLineTool.description, "Multi-line documentation")
        } else {
            XCTFail("Could not find multiLine function")
        }
        
        // Test regular comment (should use explicit description)
        if let regularCommentTool = tools.first(where: { $0.name == "regularComment" }) {
            XCTAssertEqual(regularCommentTool.description, "Explicit description needed")
        } else {
            XCTFail("Could not find regularComment function")
        }
    }
} 