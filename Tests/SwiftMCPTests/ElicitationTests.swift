import Foundation
import Testing
@testable import SwiftMCP

@Suite("Elicitation Functionality Tests")
struct ElicitationTests {

    @Suite("Elicitation Data Models")
    struct DataModelTests {

        @Test("ElicitationCreateRequest can be created and encoded/decoded")
        func elicitationCreateRequestCodableTest() throws {
            let schema = JSONSchema.object(JSONSchema.Object(
                properties: [
                    "name": .string(
                        title: nil,
                        description: "User's name",
                        format: nil,
                        minLength: nil,
                        maxLength: nil
                    ),
                    "age": .number(title: nil, description: "User's age", minimum: nil, maximum: nil)
                ],
                required: ["name"]
            ))

            let request = ElicitationCreateRequest(
                message: "Please provide your information",
                requestedSchema: schema
            )

            #expect(request.message == "Please provide your information")

            // Test encoding/decoding
            let encoder = JSONEncoder()
            let data = try encoder.encode(request)

            let decoder = JSONDecoder()
            let decodedRequest = try decoder.decode(ElicitationCreateRequest.self, from: data)

            #expect(decodedRequest.message == request.message)
        }

        @Test("ElicitationCreateResponse with accept action")
        func elicitationCreateResponseAcceptTest() throws {
            let content: JSONDictionary = [
                "name": "John Doe",
                "age": 30
            ]

            let response = ElicitationCreateResponse(action: .accept, content: content)

            #expect(response.action == .accept)
            #expect(response.content?["name"]?.value as? String == "John Doe")
            #expect(response.content?["age"]?.value as? Int == 30)

            // Test encoding/decoding
            let encoder = JSONEncoder()
            let data = try encoder.encode(response)

            let decoder = JSONDecoder()
            let decodedResponse = try decoder.decode(ElicitationCreateResponse.self, from: data)

            #expect(decodedResponse.action == .accept)
            #expect(decodedResponse.content?["name"]?.value as? String == "John Doe")
        }

        @Test("ElicitationCreateResponse with decline action")
        func elicitationCreateResponseDeclineTest() throws {
            let response = ElicitationCreateResponse(action: .decline)

            #expect(response.action == .decline)
            #expect(response.content == nil)

            // Test encoding/decoding
            let encoder = JSONEncoder()
            let data = try encoder.encode(response)

            let decoder = JSONDecoder()
            let decodedResponse = try decoder.decode(ElicitationCreateResponse.self, from: data)

            #expect(decodedResponse.action == .decline)
            #expect(decodedResponse.content == nil)
        }

        @Test("ElicitationCreateResponse with cancel action")
        func elicitationCreateResponseCancelTest() throws {
            let response = ElicitationCreateResponse(action: .cancel)

            #expect(response.action == .cancel)
            #expect(response.content == nil)
        }

        @Test("ElicitationCreateResponse action enum values")
        func elicitationActionEnumTest() throws {
            #expect(ElicitationCreateResponse.Action.accept.rawValue == "accept")
            #expect(ElicitationCreateResponse.Action.decline.rawValue == "decline")
            #expect(ElicitationCreateResponse.Action.cancel.rawValue == "cancel")
        }
    }

    @Suite("Client Capabilities Tests")
    struct ClientCapabilitiesTests {

        @Test("ClientCapabilities with elicitation support")
        func clientCapabilitiesWithElicitationTest() throws {
            let capabilities = ClientCapabilities(
                elicitation: ClientCapabilities.ElicitationCapabilities()
            )

            #expect(capabilities.elicitation != nil)

            // Test encoding/decoding
            let encoder = JSONEncoder()
            let data = try encoder.encode(capabilities)

            let decoder = JSONDecoder()
            let decoded = try decoder.decode(ClientCapabilities.self, from: data)

            #expect(decoded.elicitation != nil)
        }

        @Test("ClientCapabilities without elicitation")
        func clientCapabilitiesWithoutElicitationTest() throws {
            let capabilities = ClientCapabilities()

            #expect(capabilities.elicitation == nil)
        }

        @Test("ClientCapabilities from JSON with elicitation")
        func clientCapabilitiesFromJSONTest() throws {
            let json = """
            {
                "elicitation": {},
                "experimental": {
                    "customFeature": "enabled"
                }
            }
            """

            let data = json.data(using: .utf8)!
            let decoder = JSONDecoder()
            let capabilities = try decoder.decode(ClientCapabilities.self, from: data)

            #expect(capabilities.elicitation != nil)
            #expect(capabilities.experimental?["customFeature"]?.value as? String == "enabled")
        }

        @Test("ClientCapabilities with all capabilities")
        func clientCapabilitiesCompleteTest() throws {
            let capabilities = ClientCapabilities(
                roots: ClientCapabilities.RootsCapabilities(listChanged: true),
                sampling: ClientCapabilities.SamplingCapabilities(),
                elicitation: ClientCapabilities.ElicitationCapabilities()
            )

            #expect(capabilities.roots?.listChanged == true)
            #expect(capabilities.sampling != nil)
            #expect(capabilities.elicitation != nil)
        }
    }

    @Suite("Session Integration Tests")
    struct SessionTests {

        @Test("Session stores elicitation capabilities")
        func sessionStoresElicitationCapabilitiesTest() async {
            let session = Session(id: UUID())
            let capabilities = ClientCapabilities(
                elicitation: ClientCapabilities.ElicitationCapabilities()
            )

            await session.setClientCapabilities(capabilities)

            let storedCapabilities = await session.clientCapabilities
            #expect(storedCapabilities?.elicitation != nil)
        }

        @Test("Session setClientCapabilities with elicitation works")
        func sessionSetClientCapabilitiesElicitationTest() async {
            let session = Session(id: UUID())
            let capabilities = ClientCapabilities(
                elicitation: ClientCapabilities.ElicitationCapabilities()
            )

            await session.setClientCapabilities(capabilities)

            let storedCapabilities = await session.clientCapabilities
            #expect(storedCapabilities?.elicitation != nil)
        }
    }

    @Suite("Error Handling Tests")
    struct ErrorTests {

        @Test("MCPServerError.clientHasNoElicitationSupport error")
        func elicitationErrorTest() throws {
            let error = MCPServerError.clientHasNoElicitationSupport

            #expect(error.errorDescription == "Client does not support elicitation functionality")
        }
    }

}
