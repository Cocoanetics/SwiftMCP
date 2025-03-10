import Testing
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
}

@Test("Handles empty documentation string")
func testEmptyDocumentation() {
    let docText = ""
    let doc = Documentation(from: docText)
    #expect(doc.description == "")
    #expect(doc.parameters.isEmpty)
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
} 