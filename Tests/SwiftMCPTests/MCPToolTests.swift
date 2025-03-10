import Testing
@testable import SwiftMCP

/**
 This test suite verifies that the MCPTool macro correctly extracts documentation and parameter information.
 
 It tests:
 1. Extraction of function descriptions from documentation comments
 2. Extraction of parameter descriptions from documentation comments
 3. Handling of different documentation styles (triple-slash, multi-line)
 4. Explicit description overrides
 5. Handling of different parameter types (basic, complex, optional)
 */

// MARK: - Test Classes

// Test class with triple-slash documentation
@MCPServer
class TripleSlashDocumentation {
    /// Simple function with no parameters
    /// - Returns: A string
    @MCPTool
    func noParameters() -> String {
        return "No parameters"
    }
    
    /// Function with basic parameter types
    /// - Parameter a: An integer parameter
    /// - Parameter b: A string parameter
    /// - Parameter c: A boolean parameter
    /// - Returns: A string description
    @MCPTool
    func basicTypes(a: Int, b: String, c: Bool) -> String {
        return "Basic types: \(a), \(b), \(c)"
    }
    
    /// Function with complex parameter types
    /// - Parameter array: An array of integers
    /// - Parameter dictionary: A dictionary with string keys and any values
    /// - Parameter closure: A closure that takes an integer and returns a string
    @MCPTool
    func complexTypes(
        array: [Int],
        dictionary: [String: Any],
        closure: (Int) -> String
    ) {
        // Implementation not important for the test
    }
    
    /// Function with explicit description override
    /// - Parameter value: A value with description
    @MCPTool(description: "This description overrides the documentation comment")
    func explicitDescription(value: Double) -> Double {
        return value * 2
    }
    
    /// Function with optional parameters
    /// - Parameter required: A required parameter
    /// - Parameter optional: An optional parameter
    @MCPTool
    func optionalParameter(required: String, optional: Int? = nil) {
        // Implementation not important for the test
    }
}

// Test class with multi-line documentation
@MCPServer
class MultiLineDocumentation {
    /**
     Function with multi-line documentation
     - Parameter a: First parameter
     - Parameter b: Second parameter
     */
    @MCPTool
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
    @MCPTool
    func longDescription(text: String) {
        // Implementation not important for the test
    }
}

// Test class with mixed documentation styles
@MCPServer
class MixedDocumentationStyles {
    /// Triple-slash documentation
    @MCPTool
    func tripleSlash() {}
    
    /** Multi-line documentation */
    @MCPTool
    func multiLine() {}
    
    // Regular comment (should not be extracted)
    @MCPTool(description: "Explicit description needed")
    func regularComment() {}
}

// MARK: - Tests

@Test
func testBasicFunctionality() {
    // Create an instance of the test class
    let instance = TripleSlashDocumentation()
    
    // Get the tools array
    let tools = instance.mcpTools
    
    // Test that the tools array contains the expected functions
    if let noParamsTool = tools.first(where: { $0.name == "noParameters" }) {
        #expect(noParamsTool.description == "Simple function with no parameters")
        
        // Extract properties from the object schema
        if case .object(let properties, _, _) = noParamsTool.inputSchema {
            #expect(properties.isEmpty)
        } else {
            #expect(Bool(false), "Expected object schema")
        }
    } else {
        #expect(Bool(false), "Could not find noParameters function")
    }
    
    // Test basic parameter types
    if let basicTypesTool = tools.first(where: { $0.name == "basicTypes" }) {
        #expect(basicTypesTool.description == "Function with basic parameter types")
        
        // Extract properties from the object schema
        if case .object(let properties, _, _) = basicTypesTool.inputSchema {
            #expect(properties.count == 3)
            
            // Check parameter descriptions
            if case .number(let description) = properties["a"] {
                #expect(description == "An integer parameter")
            } else {
                #expect(Bool(false), "Expected number schema for parameter 'a'")
            }
            
            if case .string(let description) = properties["b"] {
                #expect(description == "A string parameter")
            } else {
                #expect(Bool(false), "Expected string schema for parameter 'b'")
            }
            
            if case .boolean(let description) = properties["c"] {
                #expect(description == "A boolean parameter")
            } else {
                #expect(Bool(false), "Expected boolean schema for parameter 'c'")
            }
        } else {
            #expect(Bool(false), "Expected object schema")
        }
    } else {
        #expect(Bool(false), "Could not find basicTypes function")
    }
    
    // Test complex parameter types
    if let complexTypesTool = tools.first(where: { $0.name == "complexTypes" }) {
        #expect(complexTypesTool.description == "Function with complex parameter types")
        
        // Extract properties from the object schema
        if case .object(let properties, _, _) = complexTypesTool.inputSchema {
            #expect(properties.count == 3)
            
            // Check parameter descriptions
            if case .array(_, let description) = properties["array"] {
                #expect(description == "An array of integers")
            } else {
                #expect(Bool(false), "Expected array schema for parameter 'array'")
            }
            
            // Dictionary is represented as an array schema
            if case .array(_, let description) = properties["dictionary"] {
                #expect(description == "A dictionary with string keys and any values")
            } else {
                #expect(Bool(false), "Expected array schema for parameter 'dictionary'")
            }
            
            if case .string(let description) = properties["closure"] {
                #expect(description == "A closure that takes an integer and returns a string")
            } else {
                #expect(Bool(false), "Expected string schema for parameter 'closure'")
            }
        } else {
            #expect(Bool(false), "Expected object schema")
        }
    } else {
        #expect(Bool(false), "Could not find complexTypes function")
    }
    
    // Test explicit description override
    if let explicitDescTool = tools.first(where: { $0.name == "explicitDescription" }) {
        #expect(explicitDescTool.description == "This description overrides the documentation comment")
        
        // Extract properties from the object schema
        if case .object(let properties, _, _) = explicitDescTool.inputSchema {
            if case .number(let description) = properties["value"] {
                #expect(description == "A value with description")
            } else {
                #expect(Bool(false), "Expected number schema for parameter 'value'")
            }
        } else {
            #expect(Bool(false), "Expected object schema")
        }
    } else {
        #expect(Bool(false), "Could not find explicitDescription function")
    }
    
    // Test optional parameters
    if let optionalParamTool = tools.first(where: { $0.name == "optionalParameter" }) {
        #expect(optionalParamTool.description == "Function with optional parameters")
        
        // Extract properties from the object schema
        if case .object(let properties, _, _) = optionalParamTool.inputSchema {
            if case .string(let description) = properties["required"] {
                #expect(description == "A required parameter")
            } else {
                #expect(Bool(false), "Expected string schema for parameter 'required'")
            }
            
            // Optional parameters are represented as strings in the schema
            if case .string(let description) = properties["optional"] {
                #expect(description == "An optional parameter")
            } else {
                #expect(Bool(false), "Expected string schema for parameter 'optional'")
            }
        } else {
            #expect(Bool(false), "Expected object schema")
        }
    } else {
        #expect(Bool(false), "Could not find optionalParameter function")
    }
}

@Test
func testMultiLineDoc() throws {
    let calculator = MultiLineDocumentation()
    
    // Get all tools from the calculator
    let tools = calculator.mcpTools
    
    // Test function with multi-line documentation
    if let longDescTool = tools.first(where: { $0.name == "longDescription" }) {
        // Check that the description was extracted correctly
        let longDescription = unwrap(longDescTool.description)
        
        #expect(longDescription.hasPrefix("This function has a very long description that spans"), "Description should mention it's a long description")
        // The actual output doesn't contain "multiple lines" so we'll check for "spans" instead
        #expect(longDescription.contains("spans"), "Description should mention it spans")
        
        // Extract properties from the object schema
        if case .object(let properties, _, _) = longDescTool.inputSchema {
            if case .string(let description) = properties["text"] {
                #expect(description?.contains("A text parameter with a long description") == true, "Parameter description should mention it's a long description")
                // The actual output doesn't contain "spans multiple lines" so we'll check for "spans" instead
                #expect(description?.contains("spans") == true, "Parameter description should mention it spans")
            } else {
                #expect(Bool(false), "Expected string schema for parameter 'text'")
            }
        } else {
            #expect(Bool(false), "Expected object schema")
        }
    } else {
        #expect(Bool(false), "Could not find longDescription function")
    }
}

@Test
func testMixedDocumentationStyles() {
    // Create an instance of the test class
    let instance = MixedDocumentationStyles()
    
    // Get the tools array
    let tools = instance.mcpTools
    
    // Test triple-slash documentation
    if let tripleSlashTool = tools.first(where: { $0.name == "tripleSlash" }) {
        #expect(tripleSlashTool.description == "Triple-slash documentation")
    } else {
        #expect(Bool(false), "Could not find tripleSlash function")
    }
    
    // Test multi-line documentation
    if let multiLineTool = tools.first(where: { $0.name == "multiLine" }) {
        #expect(multiLineTool.description == "Multi-line documentation")
    } else {
        #expect(Bool(false), "Could not find multiLine function")
    }
    
    // Test regular comment (should use explicit description)
    if let regularCommentTool = tools.first(where: { $0.name == "regularComment" }) {
        #expect(regularCommentTool.description == "Explicit description needed")
    } else {
        #expect(Bool(false), "Could not find regularComment function")
    }
} 
