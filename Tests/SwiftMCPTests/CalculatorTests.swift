import Testing
import SwiftMCP

@Test("Addition")
func testAdd() throws {
    let calculator = Calculator()
    
    // Test direct function call
    #expect(calculator.add(a: 2, b: 3) == 5)
    
    // Test through callTool
    let result = try calculator.callTool("add", arguments: ["a": 2, "b": 3])
    #expect(result as? Int == 5)
}

@Test
func testTestArray() throws {
    let calculator = Calculator()
    
    // Test direct function call
    #expect(calculator.testArray(a: [1, 2, 3]) == "1, 2, 3")
    
    // Test through callTool
    let result = try calculator.callTool("testArray", arguments: ["a": [1, 2, 3]])
    #expect(result as? String == "1, 2, 3")
}

@Test
func testUnknownTool() throws {
    let calculator = Calculator()
    
    do {
        _ = try calculator.callTool("unknown", arguments: [:])
        #expect(Bool(false), "Should throw an error for unknown tool")
    } catch let error as MCPToolError {
        if case .unknownTool(let name) = error {
            #expect(name == "unknown")
        } else {
            #expect(Bool(false), "Error should be unknownTool")
        }
    } catch {
        #expect(Bool(false), "Error should be MCPToolError")
    }
}

@Test
func testInvalidArgumentType() throws {
    let calculator = Calculator()
    
    do {
        _ = try calculator.callTool("add", arguments: ["a": "not_a_number", "b": 3])
        #expect(Bool(false), "Should throw an error for invalid argument type")
    } catch let error as MCPToolError {
        if case .invalidArgumentType(let parameterName, let expectedType, _) = error {
            #expect(parameterName == "a")
            #expect(expectedType == "Int")
        } else {
            #expect(Bool(false), "Error should be invalidArgumentType")
        }
    } catch {
        #expect(Bool(false), "Error should be MCPToolError")
    }
} 
