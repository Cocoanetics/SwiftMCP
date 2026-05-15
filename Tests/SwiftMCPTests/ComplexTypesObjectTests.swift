import Foundation
import Testing
@testable import SwiftMCP

// MARK: - Complex Type Tests

private func createContact(client: MockClient) async throws -> (text: String, structured: [String: Any]) {
    let createRequest = JSONRPCMessage.request(
        id: 1,
        method: "tools/call",
        params: [
            "name": "createContact",
            "arguments": [
                "name": "John Doe",
                "email": "john@example.com",
                "phone": "+1234567890",
                "age": 30,
                "isActive": true
            ]
        ]
    )

    let createMessage = await client.send(createRequest)
    guard case .response(let createResponse) = createMessage else {
        throw TestError("Expected response case")
    }
    #expect(createResponse.id == .int(1))
    let createResult = try #require(createResponse.result)
    let createIsError = try #require(createResult["isError"]?.value as? Bool)
    #expect(createIsError == false)
    let structured = try #require(createResult["structuredContent"]?.value as? [String: Any])
    let createContent = try #require(createResult["content"]?.value as? [[String: String]])
    let createFirstContent = try #require(createContent.first)
    let createText = try #require(createFirstContent["text"])
    return (createText, structured)
}

private func assertContactStructured(_ structured: [String: Any], text: String) throws {
    #expect(structured["name"] as? String == "John Doe")
    #expect(structured["email"] as? String == "john@example.com")
    #expect(structured["phone"] as? String == "+1234567890")
    #expect(structured["age"] as? Int == 30)
    #expect(structured["isActive"] as? Bool == true)
    let sortedStructuredData = try JSONSerialization.data(withJSONObject: structured, options: [.sortedKeys])
    let sortedStructuredText = try #require(String(data: sortedStructuredData, encoding: .utf8))
    #expect(sortedStructuredText == text)
}

private func processContacts(client: MockClient, contactText: String) async throws -> String {
    let processRequest = JSONRPCMessage.request(
        id: 1,
        method: "tools/call",
        params: [
            "name": "processContactArray",
            "arguments": .object([
                "contacts": .array([.string(contactText)])
            ])
        ]
    )

    let processMessage = await client.send(processRequest)
    guard case .response(let processResponse) = processMessage else {
        throw TestError("Expected response case")
    }
    #expect(processResponse.id == .int(1))
    let processResult = try #require(processResponse.result)
    let processIsError = try #require(processResult["isError"]?.value as? Bool)
    #expect(processIsError == false)
    let processContent = try #require(processResult["content"]?.value as? [[String: String]])
    let processFirstContent = try #require(processContent.first)
    return try #require(processFirstContent["text"])
}

@Test("Tests creating and processing contact info")
func testContactInfoProcessing() async throws {
    let server = ComplexTypesServer()
    let client = MockClient(server: server)

    let (createText, structured) = try await createContact(client: client)
    try assertContactStructured(structured, text: createText)

    let processText = try await processContacts(client: client, contactText: createText)

    let json = (processText as String).data(using: String.Encoding.utf8)!
    let processedWrapper = try JSONDecoder().decode(ContactInfoArrayOutput.self, from: json)
    let processedContact = try #require(processedWrapper.items.first)
    #expect(processedContact.name == "JOHN DOE")
    #expect(processedContact.email == "john@example.com")
    #expect(processedContact.phone == "+1234567890")
    #expect(processedContact.age == 60)
    #expect(processedContact.isActive == false)
}

private func createJaneContact(client: MockClient) async throws -> String {
    let contactRequest = JSONRPCMessage.request(
        id: 1,
        method: "tools/call",
        params: [
            "name": "createContact",
            "arguments": [
                "name": "Jane Doe",
                "email": "jane@example.com",
                "phone": "+1987654321",
                "age": 25,
                "isActive": true
            ]
        ]
    )

    let contactMessage = await client.send(contactRequest)
    guard case .response(let contactResponse) = contactMessage else {
        throw TestError("Expected response case")
    }
    let contactResult = try #require(contactResponse.result)
    let contactContent = try #require(contactResult["content"]?.value as? [[String: String]])
    return try #require(contactContent.first?["text"])
}

private func createAddressFor(client: MockClient) async throws -> String {
    let addressRequest = JSONRPCMessage.request(
        id: 1,
        method: "tools/call",
        params: [
            "name": "createAddress",
            "arguments": [
                "street": "123 Main St",
                "city": "New York",
                "postalCode": "10001",
                "country": "USA"
            ]
        ]
    )

    let addressMessage = await client.send(addressRequest)
    guard case .response(let addressResponse) = addressMessage else {
        throw TestError("Expected response case")
    }
    let addressResult = try #require(addressResponse.result)
    let addressContent = try #require(addressResult["content"]?.value as? [[String: String]])
    return try #require(addressContent.first?["text"])
}

private func createProfileFor(client: MockClient, contactText: String, addressText: String) async throws -> Profile {
    let profileRequest = JSONRPCMessage.request(
        id: 1,
        method: "tools/call",
        params: [
            "name": "createProfile",
            "arguments": .object([
                "contact": .string(contactText),
                "address": .string(addressText),
                "interests": .array(["reading", "gaming", "coding"]),
                "scores": .array([95, 88, 92]),
                "ratings": .array([4.5, 4.8, 4.2]),
                "activeStatuses": .array([true, false, true])
            ])
        ]
    )

    let profileMessage = await client.send(profileRequest)
    guard case .response(let profileResponse) = profileMessage else {
        throw TestError("Expected response case")
    }
    #expect(profileResponse.id == .int(1))
    let profileResult = try #require(profileResponse.result)
    let profileIsError = try #require(profileResult["isError"]?.value as? Bool)
    #expect(profileIsError == false)
    let profileContent = try #require(profileResult["content"]?.value as? [[String: String]])
    let profileFirstContent = try #require(profileContent.first)
    let profileText: String = try #require(profileFirstContent["text"])
    return try JSONDecoder().decode(Profile.self, from: profileText.data(using: String.Encoding.utf8)!)
}

@Test("Tests creating a complete profile")
func testProfileCreation() async throws {
    let server = ComplexTypesServer()
    let client = MockClient(server: server)

    let contactText = try await createJaneContact(client: client)
    let addressText = try await createAddressFor(client: client)
    let profile = try await createProfileFor(client: client, contactText: contactText, addressText: addressText)

    #expect(profile.contact.name == "Jane Doe")
    #expect(profile.contact.email == "jane@example.com")
    #expect(profile.contact.phone == "+1987654321")
    #expect(profile.contact.age == 25)
    #expect(profile.contact.isActive == true)
    #expect(profile.address.street == "123 Main St")
    #expect(profile.address.city == "New York")
    #expect(profile.address.postalCode == "10001")
    #expect(profile.address.country == "USA")
    #expect(profile.interests == ["reading", "gaming", "coding"])
    #expect(profile.scores == [95, 88, 92])
    #expect(profile.ratings == [4.5, 4.8, 4.2])
    #expect(profile.activeStatuses == [true, false, true])
}

// MARK: - Optional Array Tests

private func callOptionalArrayTool(client: MockClient, name: String) async throws -> String {
    let request = JSONRPCMessage.request(
        id: 1,
        method: "tools/call",
        params: [
            "name": .string(name),
            "arguments": [:]
        ]
    )

    let message = await client.send(request)
    guard case .response(let response) = message else {
        throw TestError("Expected response case")
    }
    let result = try #require(response.result)
    let content = try #require(result["content"]?.value as? [[String: String]])
    return try #require(content.first?["text"])
}

@Test("Tests processing of optional arrays with nil value")
func testOptionalArraysWithNil() async throws {
    let server = ComplexTypesServer()
    let client = MockClient(server: server)

    let intText = try await callOptionalArrayTool(client: client, name: "processOptionalIntArray")
    #expect(intText == "[]")

    let stringText = try await callOptionalArrayTool(client: client, name: "processOptionalStringArray")
    #expect(stringText == "[]")

    let contactText = try await callOptionalArrayTool(client: client, name: "processOptionalContactArray")
    #expect(contactText == "{\"items\":[]}")
}
