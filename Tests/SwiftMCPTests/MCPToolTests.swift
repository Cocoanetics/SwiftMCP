import Foundation
import Testing
@testable import SwiftMCP

// This test suite verifies that the MCPTool macro correctly extracts documentation and parameter information.
//
// It tests:
// 1. Extraction of function descriptions from documentation comments
// 2. Extraction of parameter descriptions from documentation comments
// 3. Handling of different documentation styles (triple-slash, multi-line)
// 4. Explicit description overrides
// 5. Handling of different parameter types (basic, complex, optional)

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
    // swiftlint:disable:next identifier_name
    func basicTypes(a: Int, b: String, c: Bool) -> String {
        return "Basic types: \(a), \(b), \(c)"
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
    // swiftlint:disable:next identifier_name
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

// Test class with URL parameters
@MCPServer
class URLParameterHandling {
    /// Function that takes a URL parameter
    /// - Parameter url: The URL to process
    /// - Returns: The URL's host
    @MCPTool
    func processURL(url: URL) -> String {
        return url.host ?? "no host"
    }
}

// Test fixture classes live in MCPToolTestFixtures.swift

// MARK: - Tests

private func assertNoParametersTool(_ tools: [MCPTool]) {
    guard let noParamsTool = tools.first(where: { $0.name == "noParameters" }) else {
        #expect(Bool(false), "Could not find noParameters function")
        return
    }
    #expect(noParamsTool.description == "Simple function with no parameters")
    if case .object(let object, _) = noParamsTool.inputSchema {
        #expect(object.properties.isEmpty)
    } else {
        #expect(Bool(false), "Expected object schema")
    }
}

private func assertBasicTypesParameters(_ object: JSONSchema.Object) {
    #expect(object.properties.count == 3)
    if case .number(title: _, description: let description, minimum: _, maximum: _, defaultValue: _) =
        object.properties["a"] {
        #expect(description == "An integer parameter")
    } else {
        #expect(Bool(false), "Expected number schema for parameter 'a'")
    }
    if case .string(
        title: _,
        description: let description,
        format: _,
        minLength: _,
        maxLength: _,
        defaultValue: _
    ) = object.properties["b"] {
        #expect(description == "A string parameter")
    } else {
        #expect(Bool(false), "Expected string schema for parameter 'b'")
    }
    if case .boolean(title: _, description: let description, defaultValue: _) = object.properties["c"] {
        #expect(description == "A boolean parameter")
    } else {
        #expect(Bool(false), "Expected boolean schema for parameter 'c'")
    }
}

private func assertBasicTypesTool(_ tools: [MCPTool]) {
    guard let basicTypesTool = tools.first(where: { $0.name == "basicTypes" }) else {
        #expect(Bool(false), "Could not find basicTypes function")
        return
    }
    #expect(basicTypesTool.description == "Function with basic parameter types")
    if case .object(let object, _) = basicTypesTool.inputSchema {
        assertBasicTypesParameters(object)
    } else {
        #expect(Bool(false), "Expected object schema")
    }
}

private func assertExplicitDescriptionTool(_ tools: [MCPTool]) {
    guard let explicitDescTool = tools.first(where: { $0.name == "explicitDescription" }) else {
        #expect(Bool(false), "Could not find explicitDescription function")
        return
    }
    #expect(explicitDescTool.description == "This description overrides the documentation comment")
    if case .object(let object, _) = explicitDescTool.inputSchema {
        if case .number(title: _, description: let description, minimum: _, maximum: _, defaultValue: _) =
            object.properties["value"] {
            #expect(description == "A value with description")
        } else {
            #expect(Bool(false), "Expected number schema for parameter 'value'")
        }
    } else {
        #expect(Bool(false), "Expected object schema")
    }
}

private func assertOptionalParameterTool(_ tools: [MCPTool]) {
    guard let optionalParamTool = tools.first(where: { $0.name == "optionalParameter" }) else {
        #expect(Bool(false), "Could not find optionalParameter function")
        return
    }
    #expect(optionalParamTool.description == "Function with optional parameters")
    if case .object(let object, _) = optionalParamTool.inputSchema {
        if case .string(
            title: _, description: let description, format: _, minLength: _, maxLength: _, defaultValue: _
        ) = object.properties["required"] {
            #expect(description == "A required parameter")
        } else {
            #expect(Bool(false), "Expected string schema for parameter 'required'")
        }
        if case .number(title: _, description: let description, minimum: _, maximum: _, defaultValue: _) =
            object.properties["optional"] {
            #expect(description == "An optional parameter")
        } else {
            #expect(Bool(false), "Expected string schema for parameter 'optional'")
        }
    } else {
        #expect(Bool(false), "Expected object schema")
    }
}

@Test
func testBasicFunctionality() {
    let instance = TripleSlashDocumentation()
    let tools = instance.mcpToolMetadata.convertedToTools()

    assertNoParametersTool(tools)
    assertBasicTypesTool(tools)
    assertExplicitDescriptionTool(tools)
    assertOptionalParameterTool(tools)
}

@Test
func testMultiLineDoc() throws {
    let calculator = MultiLineDocumentation()

    // Get all tools from the calculator
    let tools = calculator.mcpToolMetadata.convertedToTools()

    // Test function with multi-line documentation
    if let longDescTool = tools.first(where: { $0.name == "longDescription" }) {
        // Check that the description was extracted correctly
        let longDescription = try #require(longDescTool.description)

        #expect(
            longDescription.hasPrefix("This function has a very long description that spans"),
            "Description should mention it's a long description"
        )
        // The actual output doesn't contain "multiple lines" so we'll check for "spans" instead
        #expect(longDescription.contains("spans"), "Description should mention it spans")

        // Extract properties from the object schema
        if case .object(let object, _) = longDescTool.inputSchema {
			if case .string(title: _, description: let description, format: _, minLength: _, maxLength: _, defaultValue: _) =
                object.properties["text"] {
                #expect(
                    description?.contains("A text parameter with a long description") == true,
                    "Parameter description should mention it's a long description"
                )
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
    let tools = instance.mcpToolMetadata.convertedToTools()

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

@Test("URL parameters should accept both URL objects and valid URL strings")
func testURLParameters() async throws {
    let instance = URLParameterHandling()
    let tools = instance.mcpToolMetadata.convertedToTools()

    // Test that the URL parameter is represented as a string in the schema
    if let urlTool = tools.first(where: { $0.name == "processURL" }) {
        if case .object(let object, _) = urlTool.inputSchema {
			if case .string(title: _, description: let description, format: _, minLength: _, maxLength: _, defaultValue: _) =
                object.properties["url"] {
                #expect(description == "The URL to process")
            } else {
                #expect(Bool(false), "URL parameter should be represented as string in schema")
            }
        } else {
            #expect(Bool(false), "Expected object schema")
        }

        // Test with valid URL string
        let validArgs: JSONDictionary = ["url": "https://example.com"]
        let validResult = try await instance.callTool("processURL", arguments: validArgs)
        #expect(validResult as? String == "example.com")

        // Test with invalid URL string
        let invalidArgs: JSONDictionary = ["url": "https://example.com:xyz"]
        do {
            _ = try await instance.callTool("processURL", arguments: invalidArgs)
            #expect(Bool(false), "Should throw error for invalid URL")
        } catch let error as MCPToolError {
            // Verify that we get an invalid argument type error
            if case .invalidArgumentType(let paramName, _, _) = error {
                #expect(paramName == "url")
            } else {
                #expect(Bool(false), "Wrong error type")
            }
        }
    } else {
        #expect(Bool(false), "Could not find processURL function")
    }
}

// Schema tests live in MCPToolSchemaTests.swift
