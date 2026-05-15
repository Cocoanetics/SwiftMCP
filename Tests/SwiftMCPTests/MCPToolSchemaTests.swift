import Foundation
import Testing
@testable import SwiftMCP

@Test
func testSchemaRepresentableParameter() async throws {
    let instance = SchemaRepresentableTests()
    let tools = instance.mcpToolMetadata.convertedToTools()

    // Create test data
    let address = SchemaRepresentableTests.Address(street: "123 Main St", city: "New York", zip: "10001")

    // Create parameters dictionary
    let params: JSONDictionary = [
        "contact": try JSONValue(encoding: address)
    ]

    // Call the function
    let result = try await instance.callTool("fetchReminders", arguments: params)

    // Verify the result
    #expect(result as? String == "Address(street: \"123 Main St\", city: \"New York\", zip: \"10001\")")

    // Verify the schema
    if let tool = tools.first(where: { $0.name == "fetchReminders" }) {
        // Verify the schema matches the expected JSON schema
        if case .object(let object, _) = tool.inputSchema {
            #expect(object.properties.count == 1)
            #expect(object.required == ["contact"])

            // Verify the contact property
            if case .object(let object, _) = object.properties["contact"] {
                #expect(object.properties.count == 3)
                #expect(object.required == ["street", "city", "zip"])

                // Verify property types
                if case .string = object.properties["street"] {
                    // street property is correct
                } else {
                    #expect(Bool(false), "Expected string schema for street property")
                }

                if case .string = object.properties["city"] {
                    // city property is correct
                } else {
                    #expect(Bool(false), "Expected string schema for city property")
                }

                if case .string = object.properties["zip"] {
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
    if case .object(let object, _) = tool.inputSchema {
        guard let daysSchema = object.properties["days"] else {
            #expect(Bool(false), "Could not find days parameter in schema")
            return
        }

        // Verify it's an array
        if case .array(let itemsSchema, title: _, description: _, defaultValue: _) = daysSchema {
            // Verify the items are strings with enum values
            if case .enum(let enumValues, title: _, description: _, enumNames: _, defaultValue: _) = itemsSchema {

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
    if case .object(let object, _) = tool.inputSchema {
        guard let daysSchema = object.properties["days"] else {
            #expect(Bool(false), "Could not find days parameter in schema")
            return
        }

        // Verify it's not in the required array
        #expect(!object.required.contains("days"), "Optional parameter should not be required")

        // Verify it's an array
        if case .array(let itemsSchema, title: _, description: _, defaultValue: _) = daysSchema {
            // Verify the items are strings with enum values
            if case .enum(let enumValues, title: _, description: _, enumNames: _, defaultValue: _) = itemsSchema {

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
    if case .object(let object, _) = tool.inputSchema {
        guard let addressesSchema = object.properties["addresses"] else {
            #expect(Bool(false), "Could not find addresses parameter in schema")
            return
        }

        // Verify it's required
        #expect(object.required.contains("addresses"), "Required parameter should be in required array")

        // Verify it's an array
        if case .array(let itemsSchema, title: _, description: _, defaultValue: _) = addressesSchema {
            // Verify the items are objects with street and city properties
            if case .object(let object, _) = itemsSchema {
                #expect(object.properties.count == 3)
                #expect(object.required == ["street", "city", "zip"])

                // Verify property types
                if case .string = object.properties["street"] {
                    // street property is correct
                } else {
                    #expect(Bool(false), "Expected string schema for street property")
                }

                if case .string = object.properties["city"] {
                    // city property is correct
                } else {
                    #expect(Bool(false), "Expected string schema for city property")
                }

                if case .string = object.properties["zip"] {
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

    let params: JSONDictionary = [
        "addresses": try JSONValue(encoding: addresses)
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
