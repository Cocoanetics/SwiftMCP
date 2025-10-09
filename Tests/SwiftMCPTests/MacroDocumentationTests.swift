import Testing

#if canImport(SwiftCompilerPlugin) && !os(iOS)

// Note: on iOS the Documentation class from SwiftMCPMacros isn't available

@testable import SwiftMCPMacros

@Test("Parses triple-slash documentation comments")
func testTripleSlashDocumentation() {
    let docText = """
    /// Function description
    /// - Parameter a: First parameter
    /// - Parameter b: Second parameter
    """
    let doc = Documentation(from: docText)
    #expect(doc.description == "Function description")
    #expect(doc.parameters["a"] == "First parameter")
    #expect(doc.parameters["b"] == "Second parameter")
    #expect(doc.returns == nil)
}

@Test("Parses basic multi-line documentation block")
func testMultiLineDocumentation() {
    let docText = """
    /**
    Multi-line function description
    - Parameter x: X parameter
    - Parameter y: Y parameter
    */
    """
    let doc = Documentation(from: docText)
    #expect(doc.description == "Multi-line function description")
    #expect(doc.parameters["x"] == "X parameter")
    #expect(doc.parameters["y"] == "Y parameter")
    #expect(doc.returns == nil)
}

@Test("Parses formatted multi-line documentation with asterisks")
func testFormattedMultiLineDocumentation() {
    let docText = """
    /**
     * Function with formatted multi-line documentation
     * - Parameter a: First parameter
     * - Parameter b: Second parameter with
     *   multiple lines of description
     */
    """
    let doc = Documentation(from: docText)
    #expect(doc.description == "Function with formatted multi-line documentation")
    #expect(doc.parameters["a"] == "First parameter")
    #expect(doc.parameters["b"] == "Second parameter with multiple lines of description")
    #expect(doc.returns == nil)
}

@Test("Handles empty documentation string")
func testEmptyDocumentation() {
    let docText = ""
    let doc = Documentation(from: docText)
    #expect(doc.description == "")
    #expect(doc.parameters.isEmpty)
    #expect(doc.returns == nil)
}

@Test("Parses multi-line function description")
func testMultiLineDescription() {
    let docText = """
    /**
     * This is a function description
     * that spans multiple lines
     * with consistent indentation.
     *
     * - Parameter param1: First parameter
     * - Parameter param2: Second parameter
     */
    """
    let doc = Documentation(from: docText)
    #expect(doc.description == "This is a function description that spans multiple lines with consistent indentation.")
    #expect(doc.parameters["param1"] == "First parameter")
    #expect(doc.parameters["param2"] == "Second parameter")
    #expect(doc.returns == nil)
}

@Test("Parses multi-line parameter descriptions")
func testMultiLineParameterDescriptions() {
    let docText = """
    /**
     * Function with parameters that have multi-line descriptions
     * 
     * - Parameter param1: This is a parameter description
     *   that spans multiple lines with
     *   consistent indentation.
     * - Parameter param2: Another parameter with
     *   slightly different indentation
     *   pattern.
     */
    """
    let doc = Documentation(from: docText)
    #expect(doc.description == "Function with parameters that have multi-line descriptions")
    #expect(doc.parameters["param1"] == "This is a parameter description that spans multiple lines with consistent indentation.")
    #expect(doc.parameters["param2"] == "Another parameter with slightly different indentation pattern.")
    #expect(doc.returns == nil)
}

@Test("Handles mixed comment styles in a single documentation block")
func testMixedCommentStyles() {
    let docText = """
    /// This is a function with mixed comment styles
    /// that continues on a second line
    /// - Parameter mixed1: Parameter with
    /// multiple lines in triple-slash style
    /**
     * - Parameter mixed2: Parameter in block comment style
     *   with multiple lines
     */
    """
    let doc = Documentation(from: docText)
    #expect(doc.description == "This is a function with mixed comment styles that continues on a second line")
    #expect(doc.parameters["mixed1"] == "Parameter with multiple lines in triple-slash style")
    #expect(doc.parameters["mixed2"] == "Parameter in block comment style with multiple lines")
    #expect(doc.returns == nil)
}

@Test("Properly handles Returns section in documentation")
func testReturnsSection() {
    let docText = """
    /// Simple function with no parameters
    /// - Returns: A string
    """
    let doc = Documentation(from: docText)
    #expect(doc.description == "Simple function with no parameters")
    #expect(doc.returns == "A string")
    
    // Test with multi-line returns section
    let multiLineReturns = """
    /**
     * Function that returns something
     * - Returns: A complex object
     *   with multiple properties
     *   and capabilities
     */
    """
    let docWithMultiLineReturns = Documentation(from: multiLineReturns)
    #expect(docWithMultiLineReturns.description == "Function that returns something")
    #expect(docWithMultiLineReturns.returns == "A complex object with multiple properties and capabilities")
}

@Test("Handles Parameters section with dash-space format")
func testParametersDashSpace() {
    let docText = """
    /// This is a function description
    /// - Parameters:
    ///   - x: X parameter description
    ///   - y: Y parameter description
    ///   - z: Z parameter description
    """
    let doc = Documentation(from: docText)
    #expect(doc.description == "This is a function description")
    #expect(doc.parameters["x"] == "X parameter description")
    #expect(doc.parameters["y"] == "Y parameter description")
    #expect(doc.parameters["z"] == "Z parameter description")
    #expect(doc.returns == nil)
}

@Test("Handles various documentation field types")
func testVariousFieldTypes() {
    let docText = """
    /// This is a function description
    /// - Parameter x: X parameter
    /// - Returns: Return value description
    /// - Throws: Error description
    /// - Note: Additional note
    /// - Warning: Important warning
    """
    let doc = Documentation(from: docText)
    #expect(doc.description == "This is a function description")
    #expect(doc.parameters["x"] == "X parameter")
    #expect(doc.returns == "Return value description")
    // Currently we don't capture Throws and other fields, but the main point
    // is to verify they terminate the description
}

@Test("Ensures any dash-prefixed line terminates description")
func testDashTerminatesDescription() {
    let docText = """
    /// This is a function description
    /// that should be terminated by the next line
    /// - Anything: This should not be part of the description
    /// More text that should not be in the description
    """
    let doc = Documentation(from: docText)
    #expect(doc.description == "This is a function description that should be terminated by the next line")
    // The "Anything" field is not captured, but it should terminate the description
}

@Test("Handles multiple field types in sequence")
func testMultipleFieldTypes() {
    let docText = """
    /// This is a function description
    /// - Parameter x: X parameter
    /// - Important: Important note
    /// - Returns: Return value
    /// - Warning: Warning message
    /// - Throws: Error description
    """
    let doc = Documentation(from: docText)
    #expect(doc.description == "This is a function description")
    #expect(doc.parameters["x"] == "X parameter")
    #expect(doc.returns == "Return value")
    // Other fields are not captured but should not affect the parsing
}

@Test("Handles empty lines between fields")
func testEmptyLinesBetweenFields() {
    let docText = """
    /// This is a function description
    ///
    /// - Parameter x: X parameter
    ///
    /// - Returns: Return value
    ///
    /// - Note: Additional note
    """
    let doc = Documentation(from: docText)
    #expect(doc.description == "This is a function description")
    #expect(doc.parameters["x"] == "X parameter")
    #expect(doc.returns == "Return value")
}

@Test("Preserves paragraph breaks and escapes quotes in documentation")
func testParagraphBreaksAndQuotes() {
    let docText = """
    /**
     A Calculator for simple math doing additionals, subtractions etc.
     
     Testing "quoted" stuff. And on multiple lines. 'single quotes'
     */
    """
    let doc = Documentation(from: docText)
	#expect(doc.description.escapedForSwiftString == "A Calculator for simple math doing additionals, subtractions etc.\\n\\nTesting \\\"quoted\\\" stuff. And on multiple lines. \\'single quotes\\'")
}

@Test("Handles parameter descriptions with commas and newlines")
func testParameterDescriptionsWithCommasAndNewlines() {
    let docText = """
    /**
     Get reminders from the reminders app with flexible filtering options.
     
     - Parameters:
        - completed: If true, fetch completed reminders. If false, fetch incomplete reminders. If not specified, fetch all reminders.
        - startDate: ISO date string for the start of the date range to fetch reminders from
        - endDate: ISO date string for the end of the date range to fetch reminders from
        - listNames: Names of reminder lists to fetch from. If empty or not specified,
          fetches from all lists.
        - searchText: Text to search for in reminder titles
     */
    """
    let doc = Documentation(from: docText)
    #expect(doc.description == "Get reminders from the reminders app with flexible filtering options.")
    #expect(doc.parameters["completed"] == "If true, fetch completed reminders. If false, fetch incomplete reminders. If not specified, fetch all reminders.")
    #expect(doc.parameters["startDate"] == "ISO date string for the start of the date range to fetch reminders from")
    #expect(doc.parameters["endDate"] == "ISO date string for the end of the date range to fetch reminders from")
    #expect(doc.parameters["listNames"] == "Names of reminder lists to fetch from. If empty or not specified, fetches from all lists.")
    #expect(doc.parameters["searchText"] == "Text to search for in reminder titles")
    #expect(doc.returns == nil)
}

@Test("Ignores MARK comments and correctly parses documentation blocks")
func testMarkAndDocumentationBlocks() {
    let docText = """
    // MARK: - Utilities
    
    /**
       Determines the current user's date/time, language/region and time zone. Use this if that helps clarify this information for subsequent tool calls.
     */
    """
    let doc = Documentation(from: docText)
    #expect(doc.description == "Determines the current user's date/time, language/region and time zone. Use this if that helps clarify this information for subsequent tool calls.")
    #expect(doc.parameters.isEmpty)
    #expect(doc.returns == nil)
}

@Test("Handles single-line documentation blocks")
func testSingleLineDocumentationBlocks() {
    let docText = """
    /** Single line documentation */
    """
    let doc = Documentation(from: docText)
    #expect(doc.description == "Single line documentation")
    #expect(doc.parameters.isEmpty)
    #expect(doc.returns == nil)
    
    // Test with parameters
    let docWithParams = """
    /** Add two numbers - Parameter x: First number - Parameter y: Second number */
    """
    let doc2 = Documentation(from: docWithParams)
    #expect(doc2.description == "Add two numbers")
    #expect(doc2.parameters["x"] == "First number")
    #expect(doc2.parameters["y"] == "Second number")
    #expect(doc2.returns == nil)
}

#endif
