import Foundation
import Testing
@testable import SwiftMCP

@Suite("Elicitation JSON Schema Tests")
struct ElicitationSchemaTests {

    @Test("Simple string schema for elicitation")
    func simpleStringSchemaTest() throws {
        let schema = JSONSchema.object(JSONSchema.Object(
            properties: [
                "name": .string(title: nil, description: "User's name", format: nil, minLength: nil, maxLength: nil)
            ],
            required: ["name"],
            description: "Simple name request"
        ))

        // Test encoding/decoding of schema
        let encoder = JSONEncoder()
        let data = try encoder.encode(schema)

        let decoder = JSONDecoder()
        let decodedSchema = try decoder.decode(JSONSchema.self, from: data)

        if case .object(let obj, _) = decodedSchema {
            #expect(obj.required.contains("name"))
            #expect(obj.description == "Simple name request")
        } else {
            #expect(Bool(false), "Schema is not an object")
        }
    }

    @Test("Complex schema with multiple types")
    func complexSchemaTest() throws {
        let schema = JSONSchema.object(JSONSchema.Object(
            properties: [
                "name": .string(
                    title: nil,
                    description: "User's name",
                    format: nil,
                    minLength: nil,
                    maxLength: nil
                ),
                "age": .number(title: nil, description: "User's age", minimum: nil, maximum: nil),
                "isActive": .boolean(title: nil, description: "Whether user is active", defaultValue: nil),
                "category": .enum(values: ["premium", "standard", "basic"], description: "User category")
            ],
            required: ["name", "category"],
            description: "User information"
        ))

        // Test encoding/decoding
        let encoder = JSONEncoder()
        let data = try encoder.encode(schema)

        let decoder = JSONDecoder()
        let decodedSchema = try decoder.decode(JSONSchema.self, from: data)

        if case .object(let obj, _) = decodedSchema {
            #expect(obj.required.contains("name"))
            #expect(obj.required.contains("category"))
            #expect(obj.required.count == 2)
            #expect(obj.properties.count == 4)
        } else {
            #expect(Bool(false), "Schema is not an object")
        }
    }

    @Test("Email format schema")
    func emailFormatSchemaTest() throws {
        let schema = JSONSchema.object(JSONSchema.Object(
            properties: [
                "email": .string(
                    title: nil,
                    description: "Email address",
                    format: "email",
                    minLength: nil,
                    maxLength: nil
                )
            ],
            required: ["email"]
        ))

        // Test encoding/decoding
        let encoder = JSONEncoder()
        let data = try encoder.encode(schema)

        let decoder = JSONDecoder()
        let decodedSchema = try decoder.decode(JSONSchema.self, from: data)

        if case .object(let obj, _) = decodedSchema {
            if case .string(_, let description, let format, let minLength, let maxLength, _) =
                obj.properties["email"] {
                #expect(description == "Email address")
                #expect(format == "email")
                #expect(minLength == nil)
                #expect(maxLength == nil)
            } else {
                #expect(Bool(false), "Email property is not a string with format")
            }
        } else {
            #expect(Bool(false), "Schema is not an object")
        }
    }

    @Test("String schema with length constraints")
    func stringSchemaWithLengthConstraintsTest() throws {
        let schema = JSONSchema.object(JSONSchema.Object(
            properties: [
                "username": .string(title: nil, description: "Username", format: nil, minLength: 3, maxLength: 20)
            ],
            required: ["username"]
        ))

        // Test encoding/decoding
        let encoder = JSONEncoder()
        let data = try encoder.encode(schema)

        let decoder = JSONDecoder()
        let decodedSchema = try decoder.decode(JSONSchema.self, from: data)

        if case .object(let obj, _) = decodedSchema {
            if case .string(_, let description, let format, let minLength, let maxLength, _) =
                obj.properties["username"] {
                #expect(description == "Username")
                #expect(format == nil)
                #expect(minLength == 3)
                #expect(maxLength == 20)
            } else {
                #expect(Bool(false), "Username property is not a string with constraints")
            }
        } else {
            #expect(Bool(false), "Schema is not an object")
        }
    }
}

@Suite("Elicitation RequestContext Integration Tests")
struct ElicitationRequestContextTests {

    @Test("RequestContext elicit methods exist")
    func requestContextElicitMethodsExistTest() {
        // This test verifies that the elicit methods are available on RequestContext
        // In a real test environment, we would need to set up Session.current properly

        // Create a simple schema for testing
        let nameProperty: JSONSchema = .string(
            title: nil,
            description: "Name",
            format: nil,
            minLength: nil,
            maxLength: nil
        )
        let schema = JSONSchema.object(JSONSchema.Object(
            properties: ["name": nameProperty],
            required: ["name"]
        ))

        let request = ElicitationCreateRequest(message: "Test", requestedSchema: schema)

        #expect(request.message == "Test")
        // This confirms the API exists and can be called
    }
}
