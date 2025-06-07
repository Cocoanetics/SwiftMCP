import Foundation
import Testing
@testable import SwiftMCP
import AnyCodable

// MARK: - Test Types

/// A person's contact information
@Schema
struct ContactInfo: Sendable, Codable {
    /// The person's full name
    let name: String
    
    /// The person's email address
    let email: String
    
    /// The person's phone number (optional)
    let phone: String
    
    /// The person's age
    let age: Int
    
    /// Whether the person is active
    let isActive: Bool
}

/// A physical address
@Schema
struct Address: Sendable, Codable {
    /// The street address
    let street: String
    
    /// The city
    let city: String
    
    /// The postal code
    let postalCode: String
    
    /// The country
    let country: String
}

/// A profile with contact information and various data
@Schema
struct Profile: Sendable, Codable {
    /// The person's contact information
    let contact: ContactInfo
    
    /// The person's address
    let address: Address
    
    /// The person's interests
    let interests: [String]
    
    /// The person's scores
    let scores: [Int]
    
    /// The person's ratings
    let ratings: [Double]
    
    /// The person's active statuses
    let activeStatuses: [Bool]
}

/// A test server with various tools
@MCPServer(name: "ComplexTypesServer", version: "1.0")
class ComplexTypesServer {
    /// Processes an array of integers
    /// - Parameter numbers: Array of integers to process
    /// - Returns: Array of doubled integers
    @MCPTool
    func processIntArray(numbers: [Int]) -> [Int] {
        return numbers.map { $0 * 2 }
    }
    
    /// Processes an optional array of integers
    /// - Parameter numbers: Optional array of integers to process
    /// - Returns: Array of doubled integers or empty array if nil
    @MCPTool
    func processOptionalIntArray(numbers: [Int]? = nil) -> [Int] {
        return numbers?.map { $0 * 2 } ?? []
    }
    
    /// Processes an array of strings
    /// - Parameter strings: Array of strings to process
    /// - Returns: Array of uppercase strings
    @MCPTool
    func processStringArray(strings: [String]) -> [String] {
        return strings.map { $0.uppercased() }
    }
    
    /// Processes an optional array of strings
    /// - Parameter strings: Optional array of strings to process
    /// - Returns: Array of uppercase strings or empty array if nil
    @MCPTool
    func processOptionalStringArray(strings: [String]? = nil) -> [String] {
        return strings?.map { $0.uppercased() } ?? []
    }
    
    /// Processes an array of doubles
    /// - Parameter numbers: Array of doubles to process
    /// - Returns: Array of doubled doubles
    @MCPTool
    func processDoubleArray(numbers: [Double]) -> [Double] {
        return numbers.map { $0 * 2 }
    }
    
    /// Processes an optional array of doubles
    /// - Parameter numbers: Optional array of doubles to process
    /// - Returns: Array of doubled doubles or empty array if nil
    @MCPTool
    func processOptionalDoubleArray(numbers: [Double]? = nil) -> [Double] {
        return numbers?.map { $0 * 2 } ?? []
    }
    
    /// Processes an array of booleans
    /// - Parameter values: Array of booleans to process
    /// - Returns: Array of inverted booleans
    @MCPTool
    func processBooleanArray(values: [Bool]) -> [Bool] {
        return values.map { !$0 }
    }
    
    /// Processes an optional array of booleans
    /// - Parameter values: Optional array of booleans to process
    /// - Returns: Array of inverted booleans or empty array if nil
    @MCPTool
    func processOptionalBooleanArray(values: [Bool]? = nil) -> [Bool] {
        return values?.map { !$0 } ?? []
    }
    
    /// Creates a new contact
    /// - Parameters:
    ///   - name: The person's name
    ///   - email: The person's email
    ///   - phone: The person's phone number
    ///   - age: The person's age
    ///   - isActive: Whether the person is active
    /// - Returns: A new contact info object
    @MCPTool
    func createContact(name: String, email: String, phone: String, age: Int = 30, isActive: Bool = true) -> ContactInfo {
        return ContactInfo(name: name, email: email, phone: phone, age: age, isActive: isActive)
    }
    
    /// Processes an array of contacts
    /// - Parameter contacts: Array of contacts to process
    /// - Returns: Array of modified contacts
    @MCPTool
    func processContactArray(contacts: [ContactInfo]) -> [ContactInfo] {
        return contacts.map { contact in
            ContactInfo(
                name: contact.name.uppercased(),
                email: contact.email.lowercased(),
                phone: contact.phone,
                age: contact.age * 2,
                isActive: !contact.isActive
            )
        }
    }
    
    /// Processes an optional array of contacts
    /// - Parameter contacts: Optional array of contacts to process
    /// - Returns: Array of modified contacts or empty array if nil
    @MCPTool
    func processOptionalContactArray(contacts: [ContactInfo]? = nil) -> [ContactInfo] {
        return contacts?.map { contact in
            ContactInfo(
                name: contact.name.uppercased(),
                email: contact.email.lowercased(),
                phone: contact.phone,
                age: contact.age * 2,
                isActive: !contact.isActive
            )
        } ?? []
    }
    
    /// Creates a new address
    /// - Parameters:
    ///   - street: The street address
    ///   - city: The city name
    ///   - postalCode: The postal code
    ///   - country: The country name
    /// - Returns: A new address object
    @MCPTool
    func createAddress(street: String, city: String, postalCode: String, country: String) -> Address {
        return Address(street: street, city: city, postalCode: postalCode, country: country)
    }
    
    /// Creates a new profile
    /// - Parameters:
    ///   - contact: The contact information
    ///   - address: The address information
    ///   - interests: Array of interests
    ///   - scores: Array of scores
    ///   - ratings: Array of ratings
    ///   - activeStatuses: Array of active statuses
    /// - Returns: A new profile object
    @MCPTool
    func createProfile(contact: ContactInfo, address: Address, interests: [String] = [], scores: [Int] = [], ratings: [Double] = [], activeStatuses: [Bool] = []) -> Profile {
        return Profile(contact: contact, address: address, interests: interests, scores: scores, ratings: ratings, activeStatuses: activeStatuses)
    }
}

// MARK: - Tests

// MARK: - Basic Type Tests

@Test("Tests processing of integer arrays")
func testIntArrayProcessing() async throws {
    let server = ComplexTypesServer()
    let client = MockClient(server: server)
    
    let request = JSONRPCMessage.request(
        id: 1,
        method: "tools/call",
        params: [
            "name": "processIntArray",
            "arguments": [
                "numbers": [1, 2, 3, 4, 5]
            ]
        ]
    )
    
    let message = await client.send(request)
    guard case .response(let response) = message else {
        #expect(Bool(false), "Expected response case")
        return
    }
    #expect(response.id == 1)
    let result = try #require(response.result)
    let isError = try #require(result["isError"]?.value as? Bool)
    #expect(isError == false)
    let content = try #require(result["content"]?.value as? [[String: String]])
    let firstContent = try #require(content.first)
    let type = try #require(firstContent["type"])
    let text = try #require(firstContent["text"])
    #expect(type == "text")
    #expect(text == "[2,4,6,8,10]")
}

@Test("Tests processing of optional integer arrays")
func testOptionalIntArrayProcessing() async throws {
    let server = ComplexTypesServer()
    let client = MockClient(server: server)
    
    let request = JSONRPCMessage.request(
        id: 1,
        method: "tools/call",
        params: [
            "name": "processOptionalIntArray",
            "arguments": [:]
        ]
    )
    
    let message = await client.send(request)
    guard case .response(let response) = message else {
        #expect(Bool(false), "Expected response case")
        return
    }
    #expect(response.id == 1)
    let result = try #require(response.result)
    let isError = try #require(result["isError"]?.value as? Bool)
    #expect(isError == false)
    let content = try #require(result["content"]?.value as? [[String: String]])
    let firstContent = try #require(content.first)
    let type = try #require(firstContent["type"])
    let text = try #require(firstContent["text"])
    #expect(type == "text")
    #expect(text == "[]")
}

@Test("Tests processing of string arrays")
func testStringArrayProcessing() async throws {
    let server = ComplexTypesServer()
    let client = MockClient(server: server)
    
    let request = JSONRPCMessage.request(
        id: 1,
        method: "tools/call",
        params: [
            "name": "processStringArray",
            "arguments": [
                "strings": ["hello", "world", "test"]
            ]
        ]
    )
    
    let message = await client.send(request)
    guard case .response(let response) = message else {
        #expect(Bool(false), "Expected response case")
        return
    }
    #expect(response.id == 1)
    let result = try #require(response.result)
    let isError = try #require(result["isError"]?.value as? Bool)
    #expect(isError == false)
    let content = try #require(result["content"]?.value as? [[String: String]])
    let firstContent = try #require(content.first)
    let type = try #require(firstContent["type"])
    let text = try #require(firstContent["text"])
    #expect(type == "text")
    #expect(text == "[\"HELLO\",\"WORLD\",\"TEST\"]")
}

@Test("Tests processing of double arrays")
func testDoubleArrayProcessing() async throws {
    let server = ComplexTypesServer()
    let client = MockClient(server: server)
    
    let request = JSONRPCMessage.request(
        id: 1,
        method: "tools/call",
        params: [
            "name": "processDoubleArray",
            "arguments": [
                "numbers": [1.1, 2.2, 3.3]
            ]
        ]
    )
    
    let message = await client.send(request)
    guard case .response(let response) = message else {
        #expect(Bool(false), "Expected response case")
        return
    }
    #expect(response.id == 1)
    let result = try #require(response.result)
    let isError = try #require(result["isError"]?.value as? Bool)
    #expect(isError == false)
    let content = try #require(result["content"]?.value as? [[String: String]])
    let firstContent = try #require(content.first)
    let type = try #require(firstContent["type"])
    let text = try #require(firstContent["text"])
    #expect(type == "text")
    #expect(text == "[2.2,4.4,6.6]")
}

@Test("Tests processing of optional double arrays")
func testOptionalDoubleArrayProcessing() async throws {
    let server = ComplexTypesServer()
    let client = MockClient(server: server)
    
    let request = JSONRPCMessage.request(
        id: 1,
        method: "tools/call",
        params: [
            "name": "processOptionalDoubleArray",
            "arguments": [
                "numbers": [1.1, 2.2, 3.3]
            ]
        ]
    )
    
    let message = await client.send(request)
    guard case .response(let response) = message else {
        #expect(Bool(false), "Expected response case")
        return
    }
    #expect(response.id == 1)
    let result = try #require(response.result)
    let isError = try #require(result["isError"]?.value as? Bool)
    #expect(isError == false)
    let content = try #require(result["content"]?.value as? [[String: String]])
    let firstContent = try #require(content.first)
    let type = try #require(firstContent["type"])
    let text = try #require(firstContent["text"])
    #expect(type == "text")
    #expect(text == "[2.2,4.4,6.6]")
}

@Test("Tests processing of boolean arrays")
func testBooleanArrayProcessing() async throws {
    let server = ComplexTypesServer()
    let client = MockClient(server: server)
    
    let request = JSONRPCMessage.request(
        id: 1,
        method: "tools/call",
        params: [
            "name": "processBooleanArray",
            "arguments": [
                "values": [true, false, true]
            ]
        ]
    )
    
    let message = await client.send(request)
    guard case .response(let response) = message else {
        #expect(Bool(false), "Expected response case")
        return
    }
    #expect(response.id == 1)
    let result = try #require(response.result)
    let isError = try #require(result["isError"]?.value as? Bool)
    #expect(isError == false)
    let content = try #require(result["content"]?.value as? [[String: String]])
    let firstContent = try #require(content.first)
    let type = try #require(firstContent["type"])
    let text = try #require(firstContent["text"])
    #expect(type == "text")
    #expect(text == "[false,true,false]")
}

@Test("Tests processing of optional boolean arrays")
func testOptionalBooleanArrayProcessing() async throws {
    let server = ComplexTypesServer()
    let client = MockClient(server: server)
    
    let request = JSONRPCMessage.request(
        id: 1,
        method: "tools/call",
        params: [
            "name": "processOptionalBooleanArray",
            "arguments": [
                "values": [true, false, true]
            ]
        ]
    )
    
    let message = await client.send(request)
    guard case .response(let response) = message else {
        #expect(Bool(false), "Expected response case")
        return
    }
    #expect(response.id == 1)
    let result = try #require(response.result)
    let isError = try #require(result["isError"]?.value as? Bool)
    #expect(isError == false)
    let content = try #require(result["content"]?.value as? [[String: String]])
    let firstContent = try #require(content.first)
    let type = try #require(firstContent["type"])
    let text = try #require(firstContent["text"])
    #expect(type == "text")
    #expect(text == "[false,true,false]")
}

// MARK: - Complex Type Tests

@Test("Tests creating and processing contact info")
func testContactInfoProcessing() async throws {
    let server = ComplexTypesServer()
    let client = MockClient(server: server)
    
    // First create a contact
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
        #expect(Bool(false), "Expected response case")
        return
    }
    #expect(createResponse.id == 1)
    let createResult = try #require(createResponse.result)
    let createIsError = try #require(createResult["isError"]?.value as? Bool)
    #expect(createIsError == false)
    let createContent = try #require(createResult["content"]?.value as? [[String: String]])
    let createFirstContent = try #require(createContent.first)
    let createText = try #require(createFirstContent["text"])
    
    // Now process the contact array
    let processRequest = JSONRPCMessage.request(
        id: 1,
        method: "tools/call",
        params: [
            "name": "processContactArray",
            "arguments": [
                "contacts": [createText]
            ]
        ]
    )
    
    let processMessage = await client.send(processRequest)
    guard case .response(let processResponse) = processMessage else {
        #expect(Bool(false), "Expected response case")
        return
    }
    #expect(processResponse.id == 1)
    let processResult = try #require(processResponse.result)
    let processIsError = try #require(processResult["isError"]?.value as? Bool)
    #expect(processIsError == false)
    let processContent = try #require(processResult["content"]?.value as? [[String: String]])
    let processFirstContent = try #require(processContent.first)
    let processText = try #require(processFirstContent["text"])
    
    // Verify the processed contact
    let json = processText.data(using: .utf8)!
    let processedContacts = try JSONDecoder().decode([ContactInfo].self, from: json)
    let processedContact = try #require(processedContacts.first)
    #expect(processedContact.name == "JOHN DOE")
    #expect(processedContact.email == "john@example.com")
    #expect(processedContact.phone == "+1234567890")
    #expect(processedContact.age == 60)
    #expect(processedContact.isActive == false)
}

@Test("Tests creating a complete profile")
func testProfileCreation() async throws {
    let server = ComplexTypesServer()
    let client = MockClient(server: server)
    
    // First create a contact
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
        #expect(Bool(false), "Expected response case")
        return
    }
    let contactResult = try #require(contactResponse.result)
    let contactContent = try #require(contactResult["content"]?.value as? [[String: String]])
    let contactText = try #require(contactContent.first?["text"])
    
    // Create an address
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
        #expect(Bool(false), "Expected response case")
        return
    }
    let addressResult = try #require(addressResponse.result)
    let addressContent = try #require(addressResult["content"]?.value as? [[String: String]])
    let addressText = try #require(addressContent.first?["text"])
    
    // Create the profile
    let profileRequest = JSONRPCMessage.request(
        id: 1,
        method: "tools/call",
        params: [
            "name": "createProfile",
            "arguments": [
                "contact": contactText,
                "address": addressText,
                "interests": ["reading", "gaming", "coding"],
                "scores": [95, 88, 92],
                "ratings": [4.5, 4.8, 4.2],
                "activeStatuses": [true, false, true]
            ]
        ]
    )
    
    let profileMessage = await client.send(profileRequest)
    guard case .response(let profileResponse) = profileMessage else {
        #expect(Bool(false), "Expected response case")
        return
    }
    #expect(profileResponse.id == 1)
    let profileResult = try #require(profileResponse.result)
    let profileIsError = try #require(profileResult["isError"]?.value as? Bool)
    #expect(profileIsError == false)
    let profileContent = try #require(profileResult["content"]?.value as? [[String: String]])
    let profileText = try #require(profileContent.first?["text"] as? String)
    let profile = try JSONDecoder().decode(Profile.self, from: (profileText as String).data(using: .utf8)!)
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

@Test("Tests processing of optional arrays with nil value")
func testOptionalArraysWithNil() async throws {
    let server = ComplexTypesServer()
    let client = MockClient(server: server)
    
    // Test optional int array with nil
    let intRequest = JSONRPCMessage.request(
        id: 1,
        method: "tools/call",
        params: [
            "name": "processOptionalIntArray",
            "arguments": [:]
        ]
    )
    
    let intMessage = await client.send(intRequest)
    guard case .response(let intResponse) = intMessage else {
        #expect(Bool(false), "Expected response case")
        return
    }
    let intResult = try #require(intResponse.result)
    let intContent = try #require(intResult["content"]?.value as? [[String: String]])
    let intText = try #require(intContent.first?["text"])
    #expect(intText == "[]")
    
    // Test optional string array with nil
    let stringRequest = JSONRPCMessage.request(
        id: 1,
        method: "tools/call",
        params: [
            "name": "processOptionalStringArray",
            "arguments": [:]
        ]
    )
    
    let stringMessage = await client.send(stringRequest)
    guard case .response(let stringResponse) = stringMessage else {
        #expect(Bool(false), "Expected response case")
        return
    }
    let stringResult = try #require(stringResponse.result)
    let stringContent = try #require(stringResult["content"]?.value as? [[String: String]])
    let stringText = try #require(stringContent.first?["text"])
    #expect(stringText == "[]")
    
    // Test optional contact array with nil
    let contactRequest = JSONRPCMessage.request(
        id: 1,
        method: "tools/call",
        params: [
            "name": "processOptionalContactArray",
            "arguments": [:]
        ]
    )
    
    let contactMessage = await client.send(contactRequest)
    guard case .response(let contactResponse) = contactMessage else {
        #expect(Bool(false), "Expected response case")
        return
    }
    let contactResult = try #require(contactResponse.result)
    let contactContent = try #require(contactResult["content"]?.value as? [[String: String]])
    let contactText = try #require(contactContent.first?["text"])
    #expect(contactText == "[]")
} 
