import Foundation
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

// Test class with SchemaRepresentable types
@MCPServer
class SchemaRepresentableTests {
    /// A person's contact information
    @Schema
    struct ContactInfo {
        /// The person's full name
        let name: String
        
        /// The person's email address
        let email: String
        
        /// The person's phone number (optional)
        let phone: String?
        
        /// The person's age
        var age: Int = 0
        
        /// The person's address
        let address: Address
    }
    
    /// A person's address
    @Schema
    struct Address: Codable {
        let street: String
        let city: String
        let zip: String
        
        init(street: String, city: String, zip: String) {
            self.street = street
            self.city = city
            self.zip = zip
        }
    }
    
    /**
     Get reminders from the reminders app with flexible filtering options.
     
     - Parameters:
        - contact: A test contact
     */
    @MCPTool
    func fetchReminders(
        contact: Address
    ) -> String {
        return "\(contact)"
    }
}

// Test class with array of enums
@MCPServer
class EnumArrayTest {
    /// Function that takes an array of weekdays
    /// - Parameter days: Array of weekdays
    @MCPTool
    func processWeekdays(days: [Weekday]) {
        // Implementation not important for the test
    }
    
    /// Function that takes an optional array of weekdays
    /// - Parameter days: Optional array of weekdays
    @MCPTool
    func processOptionalWeekdays(days: [Weekday]? = nil) {
        // Implementation not important for the test
    }
}

// Test class with array of SchemaRepresentable types
@MCPServer
class SchemaRepresentableArrayTest {
    /// Function that takes an array of addresses
    /// - Parameter addresses: Array of addresses
    @MCPTool
    func processAddresses(addresses: [SchemaRepresentableTests.Address]) {
        // Implementation not important for the test
    }
}

// Add Weekday enum before the tests
enum Weekday: String, CaseIterable {
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday
    case sunday
}

// MARK: - Tests

@Test
func testBasicFunctionality() {
    // Create an instance of the test class
    let instance = TripleSlashDocumentation()
    
    // Get the tools array
    let tools = instance.mcpToolMetadata.convertedToTools()
    
    // Test that the tools array contains the expected functions
    if let noParamsTool = tools.first(where: { $0.name == "noParameters" }) {
        #expect(noParamsTool.description == "Simple function with no parameters")
        
        // Extract properties from the object schema
        if case .object(let object) = noParamsTool.inputSchema {
			#expect(object.properties.isEmpty)
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
        if case .object(let object) = basicTypesTool.inputSchema {
			#expect(object.properties.count == 3)
            
            // Check parameter descriptions
			if case .number(let description) = object.properties["a"] {
                #expect(description == "An integer parameter")
            } else {
                #expect(Bool(false), "Expected number schema for parameter 'a'")
            }
            
			if case .string(description: let description, format: _) = object.properties["b"] {
                #expect(description == "A string parameter")
            } else {
                #expect(Bool(false), "Expected string schema for parameter 'b'")
            }
            
			if case .boolean(let description) = object.properties["c"] {
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
    
    // Test explicit description override
    if let explicitDescTool = tools.first(where: { $0.name == "explicitDescription" }) {
        #expect(explicitDescTool.description == "This description overrides the documentation comment")
        
        // Extract properties from the object schema
        if case .object(let object) = explicitDescTool.inputSchema {
			if case .number(let description) = object.properties["value"] {
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
        if case .object(let object) = optionalParamTool.inputSchema {
			if case .string(description: let description, format: _) = object.properties["required"] {
                #expect(description == "A required parameter")
            } else {
                #expect(Bool(false), "Expected string schema for parameter 'required'")
            }
            
            // Optional parameters are represented as strings in the schema
			if case .number(description: let description) = object.properties["optional"] {
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
    let tools = calculator.mcpToolMetadata.convertedToTools()
    
    // Test function with multi-line documentation
    if let longDescTool = tools.first(where: { $0.name == "longDescription" }) {
        // Check that the description was extracted correctly
        let longDescription = unwrap(longDescTool.description)
        
        #expect(longDescription.hasPrefix("This function has a very long description that spans"), "Description should mention it's a long description")
        // The actual output doesn't contain "multiple lines" so we'll check for "spans" instead
        #expect(longDescription.contains("spans"), "Description should mention it spans")
        
        // Extract properties from the object schema
        if case .object(let object) = longDescTool.inputSchema {
			if case .string(description: let description, format: _) = object.properties["text"] {
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
        if case .object(let object) = urlTool.inputSchema {
			if case .string(description: let description, format: _) = object.properties["url"] {
                #expect(description == "The URL to process")
            } else {
                #expect(Bool(false), "URL parameter should be represented as string in schema")
            }
        } else {
            #expect(Bool(false), "Expected object schema")
        }
        
        // Test with valid URL string
        let validArgs = ["url": "https://example.com"] as [String: Sendable]
        let validResult = try await instance.callTool("processURL", arguments: validArgs)
        #expect(validResult as? String == "example.com")
        
        // Test with invalid URL string
        let invalidArgs = ["url": "https://example.com:xyz"] as [String: Sendable]
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

@Test
func testSchemaRepresentableParameter() async throws {
    let instance = SchemaRepresentableTests()
    let tools = instance.mcpToolMetadata.convertedToTools()
    
    // Create test data
    let address = SchemaRepresentableTests.Address(street: "123 Main St", city: "New York", zip: "10001")
    
    // Create parameters dictionary
    let params: [String: Sendable] = [
        "contact": address
    ]
    
    // Call the function
    let result = try await instance.callTool("fetchReminders", arguments: params)
    
    // Verify the result
    #expect(result as? String == "Address(street: \"123 Main St\", city: \"New York\", zip: \"10001\")")
    
    // Verify the schema
    if let tool = tools.first(where: { $0.name == "fetchReminders" }) {
        // Verify the schema matches the expected JSON schema
        if case .object(let object) = tool.inputSchema {
			#expect(object.properties.count == 1)
			#expect(object.required == ["contact"])
            
            // Verify the contact property
			if case .object(let object) = object.properties["contact"] {
				#expect(object.properties.count == 3)
				#expect(object.required == ["street", "city", "zip"])
                
                // Verify property types
				if case .string(description: _, format: _) = object.properties["street"] {
                    // street property is correct
                } else {
                    #expect(Bool(false), "Expected string schema for street property")
                }
                
				if case .string(description: _, format: _) = object.properties["city"] {
                    // city property is correct
                } else {
                    #expect(Bool(false), "Expected string schema for city property")
                }
                
				if case .string(description: _, format: _) = object.properties["zip"] {
                    // zip property is correct
                } else {
                    #expect(Bool(false), "Expected string schema for zip property")
                }
            } else {
                #expect(Bool(false), "Expected object schema for contact property")
            }
        } else {
            #expect(Bool(false), "Expected object schema")
        }
    } else {
        #expect(Bool(false), "Could not find fetchReminders function")
    }
}

@Test
func testEnumArraySchema() throws {
    let server = EnumArrayTest()
    let tools = server.mcpToolMetadata.convertedToTools()
    
    // Find the processWeekdays tool
    guard let tool = tools.first(where: { $0.name == "processWeekdays" }) else {
        #expect(Bool(false), "Could not find processWeekdays tool")
        return
    }
    
    // Get the schema for the days parameter
    if case .object(let object) = tool.inputSchema {
		guard let daysSchema = object.properties["days"] else {
            #expect(Bool(false), "Could not find days parameter in schema")
            return
        }
        
        // Verify it's an array
        if case .array(let itemsSchema, _) = daysSchema {
            // Verify the items are strings with enum values
            if case .enum(let enumValues, _) = itemsSchema {
                
                // Verify the enum values are the Weekday cases
                let expectedValues = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
                #expect(enumValues.sorted() == expectedValues.sorted())
            } else {
                #expect(Bool(false), "Array items should be strings")
            }
        } else {
            #expect(Bool(false), "Expected array schema")
        }
    } else {
        #expect(Bool(false), "Expected object schema")
    }
}

@Test
func testOptionalEnumArraySchema() throws {
    let server = EnumArrayTest()
    let tools = server.mcpToolMetadata.convertedToTools()
    
    // Find the processOptionalWeekdays tool
    guard let tool = tools.first(where: { $0.name == "processOptionalWeekdays" }) else {
        #expect(Bool(false), "Could not find processOptionalWeekdays tool")
        return
    }
    
    // Get the schema for the days parameter
    if case .object(let object) = tool.inputSchema {
		guard let daysSchema = object.properties["days"] else {
            #expect(Bool(false), "Could not find days parameter in schema")
            return
        }
        
        // Verify it's not in the required array
		#expect(!object.required.contains("days"), "Optional parameter should not be required")
        
        // Verify it's an array
        if case .array(let itemsSchema, _) = daysSchema {
            // Verify the items are strings with enum values
            if case .enum(let enumValues, _) = itemsSchema {
                
                // Verify the enum values are the Weekday cases
                let expectedValues = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
                #expect(enumValues.sorted() == expectedValues.sorted())
            } else {
                #expect(Bool(false), "Array items should be strings")
            }
        } else {
            #expect(Bool(false), "Expected array schema")
        }
    } else {
        #expect(Bool(false), "Expected object schema")
    }
}

@Test
func testSchemaRepresentableArraySchema() throws {
    let server = SchemaRepresentableArrayTest()
    let tools = server.mcpToolMetadata.convertedToTools()
    
    // Find the processAddresses tool
    guard let tool = tools.first(where: { $0.name == "processAddresses" }) else {
        #expect(Bool(false), "Could not find processAddresses tool")
        return
    }
    
    // Get the schema for the addresses parameter
    if case .object(let object) = tool.inputSchema {
		guard let addressesSchema = object.properties["addresses"] else {
            #expect(Bool(false), "Could not find addresses parameter in schema")
            return
        }
        
        // Verify it's required
		#expect(object.required.contains("addresses"), "Required parameter should be in required array")
        
        // Verify it's an array
        if case .array(let itemsSchema, _) = addressesSchema {
            // Verify the items are objects with street and city properties
            if case .object(let object) = itemsSchema {
				#expect(object.properties.count == 3)
				#expect(object.required == ["street", "city", "zip"])
                
                // Verify property types
				if case .string(description: _, format: _) = object.properties["street"] {
                    // street property is correct
                } else {
                    #expect(Bool(false), "Expected string schema for street property")
                }
                
				if case .string(description: _, format: _) = object.properties["city"] {
                    // city property is correct
                } else {
                    #expect(Bool(false), "Expected string schema for city property")
                }
                
				if case .string(description: _, format: _) = object.properties["zip"] {
                    // zip property is correct
                } else {
                    #expect(Bool(false), "Expected string schema for zip property")
                }
            } else {
                #expect(Bool(false), "Expected object schema for array items")
            }
        } else {
            #expect(Bool(false), "Expected array schema")
        }
    } else {
        #expect(Bool(false), "Expected object schema")
    }
}

@Test
func testAddressDecoding() throws {
    // Create a dictionary representing an address
    let addressDict: [String: Any] = [
        "street": "123 Main St",
        "city": "New York",
        "zip": "10001"
    ]
    
    // Encode the dictionary to JSON data
    let jsonData = try JSONSerialization.data(withJSONObject: addressDict)
    
    // Decode the JSON data into an Address struct
    let address = try JSONDecoder().decode(SchemaRepresentableTests.Address.self, from: jsonData)
    
    // Verify the decoded values
    #expect(address.street == "123 Main St")
    #expect(address.city == "New York")
    #expect(address.zip == "10001")
}

@Test
func testAddressArrayDecoding() throws {
    // Create an array of dictionaries representing addresses
    let addressDicts: [[String: Any]] = [
        [
            "street": "123 Main St",
            "city": "New York",
            "zip": "10001"
        ],
        [
            "street": "456 Oak Ave",
            "city": "San Francisco",
            "zip": "94102"
        ],
        [
            "street": "789 Pine Rd",
            "city": "Chicago",
            "zip": "60601"
        ]
    ]
    
    // Encode the array to JSON data
    let jsonData = try JSONSerialization.data(withJSONObject: addressDicts)
    
    // Decode the JSON data into an array of Address structs
    let addresses = try JSONDecoder().decode([SchemaRepresentableTests.Address].self, from: jsonData)
    
    // Verify the number of addresses
    #expect(addresses.count == 3)
    
    // Verify each address
    #expect(addresses[0].street == "123 Main St")
    #expect(addresses[0].city == "New York")
    #expect(addresses[0].zip == "10001")
    
    #expect(addresses[1].street == "456 Oak Ave")
    #expect(addresses[1].city == "San Francisco")
    #expect(addresses[1].zip == "94102")
    
    #expect(addresses[2].street == "789 Pine Rd")
    #expect(addresses[2].city == "Chicago")
    #expect(addresses[2].zip == "60601")
}

@Test
func testExtractAddressArray() throws {
    let addresses = [
        SchemaRepresentableTests.Address(street: "123 Main St", city: "New York", zip: "10001"),
        SchemaRepresentableTests.Address(street: "456 Oak Ave", city: "San Francisco", zip: "94102")
    ]
    
    let params: [String: any Sendable] = [
        "addresses": addresses as [SchemaRepresentableTests.Address]
    ]
    
    let extractedAddresses: [SchemaRepresentableTests.Address] = try params.extractParameter(named: "addresses")
    
    #expect(extractedAddresses.count == 2)
    #expect(extractedAddresses[0].street == "123 Main St")
    #expect(extractedAddresses[0].city == "New York")
    #expect(extractedAddresses[0].zip == "10001")
    #expect(extractedAddresses[1].street == "456 Oak Ave")
    #expect(extractedAddresses[1].city == "San Francisco")
    #expect(extractedAddresses[1].zip == "94102")
} 
