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
    
    let request = JSONRPCRequest(
        id: 1,
        method: "tools/call",
        params: [
            "name": "processIntArray",
            "arguments": [
                "numbers": [1, 2, 3, 4, 5]
            ]
        ]
    )
    
	let response = unwrap(await client.send(request) as? JSONRPCResponse)
    
    #expect(response.id == 1)
    
    let result = unwrap(response.result)
    let isError = unwrap(result["isError"]?.value as? Bool)
    #expect(isError == false)
    
    let content = unwrap(result["content"]?.value as? [[String: String]])
    let firstContent = unwrap(content.first)
    let type = unwrap(firstContent["type"])
    let text = unwrap(firstContent["text"])
    
    #expect(type == "text")
    #expect(text == "[2,4,6,8,10]")
}

@Test("Tests processing of optional integer arrays")
func testOptionalIntArrayProcessing() async throws {
    let server = ComplexTypesServer()
    let client = MockClient(server: server)
    
    let request = JSONRPCRequest(
        id: 1,
        method: "tools/call",
        params: [
            "name": "processOptionalIntArray",
            "arguments": [
                "numbers": [1, 2, 3, 4, 5]
            ]
        ]
    )
    
    let response = unwrap(await client.send(request) as? JSONRPCResponse)
    
    #expect(response.id == 1)
    
    let result = unwrap(response.result)
    let isError = unwrap(result["isError"]?.value as? Bool)
    #expect(isError == false)
    
    let content = unwrap(result["content"]?.value as? [[String: String]])
    let firstContent = unwrap(content.first)
    let type = unwrap(firstContent["type"])
    let text = unwrap(firstContent["text"])
    
    #expect(type == "text")
    #expect(text == "[2,4,6,8,10]")
}

@Test("Tests processing of string arrays")
func testStringArrayProcessing() async throws {
    let server = ComplexTypesServer()
    let client = MockClient(server: server)
    
    let request = JSONRPCRequest(
        id: 1,
        method: "tools/call",
        params: [
            "name": AnyCodable("processStringArray"),
            "arguments": AnyCodable([
                "strings": ["hello", "world", "test"]
            ])
        ]
    )
    
    let response = unwrap(await client.send(request) as? JSONRPCResponse)
    
    #expect(response.id == 1)
    
    let result = unwrap(response.result)
    let isError = unwrap(result["isError"]?.value as? Bool)
    #expect(isError == false)
    
    let content = unwrap(result["content"]?.value as? [[String: String]])
    let firstContent = unwrap(content.first)
    let type = unwrap(firstContent["type"])
    let text = unwrap(firstContent["text"])
    
    #expect(type == "text")
    #expect(text == "[\"HELLO\",\"WORLD\",\"TEST\"]")
}

// MARK: - Complex Type Tests

@Test("Tests creating and processing contact info")
func testContactInfoProcessing() async throws {
    let server = ComplexTypesServer()
    let client = MockClient(server: server)
    
    // First create a contact
    let createRequest = JSONRPCRequest(
        id: 1,
        method: "tools/call",
        params: [
            "name": AnyCodable("createContact"),
            "arguments": AnyCodable([
                "name": "John Doe",
                "email": "john@example.com",
                "phone": "+1234567890",
                "age": 30,
                "isActive": true
            ])
        ]
    )
    
    let createResponse = unwrap(await client.send(createRequest) as? JSONRPCResponse)
    
    #expect(createResponse.id == 1)
    
    let createResult = unwrap(createResponse.result)
    let createIsError = unwrap(createResult["isError"]?.value as? Bool)
    #expect(createIsError == false)
    
    let createContent = unwrap(createResult["content"]?.value as? [[String: String]])
    let createFirstContent = unwrap(createContent.first)
    let createText = unwrap(createFirstContent["text"])
    
    // Now process the contact array
    let processRequest = JSONRPCRequest(
        id: 1,
        method: "tools/call",
        params: [
            "name": AnyCodable("processContactArray"),
            "arguments": AnyCodable([
                "contacts": [createText]
            ])
        ]
    )
    
	let processResponse = unwrap(await client.send(processRequest) as? JSONRPCResponse)
    
    #expect(processResponse.id == 1)
    
    let processResult = unwrap(processResponse.result)
    let processIsError = unwrap(processResult["isError"]?.value as? Bool)
    #expect(processIsError == false)
    
    let processContent = unwrap(processResult["content"]?.value as? [[String: String]])
    let processFirstContent = unwrap(processContent.first)
    let processText = unwrap(processFirstContent["text"])
    
    // Verify the processed contact
    let json = processText.data(using: .utf8)!
    let processedContacts = try JSONDecoder().decode([ContactInfo].self, from: json)
    let processedContact = unwrap(processedContacts.first)
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
    let contactRequest = JSONRPCRequest(
        id: 1,
        method: "tools/call",
        params: [
            "name": AnyCodable("createContact"),
            "arguments": AnyCodable([
                "name": "Jane Doe",
                "email": "jane@example.com",
                "phone": "+1987654321",
                "age": 25,
                "isActive": true
            ])
        ]
    )
    
    let contactResponse = unwrap(await client.send(contactRequest) as? JSONRPCResponse)
    let contactResult = unwrap(contactResponse.result)
    let contactContent = unwrap(contactResult["content"]?.value as? [[String: String]])
    let contactText = unwrap(contactContent.first?["text"])
    
    // Create an address
    let addressRequest = JSONRPCRequest(
        id: 1,
        method: "tools/call",
        params: [
            "name": AnyCodable("createAddress"),
            "arguments": AnyCodable([
                "street": "123 Main St",
                "city": "New York",
                "postalCode": "10001",
                "country": "USA"
            ])
        ]
    )
    
    let addressResponse = unwrap(await client.send(addressRequest) as? JSONRPCResponse)
    let addressResult = unwrap(addressResponse.result)
    let addressContent = unwrap(addressResult["content"]?.value as? [[String: String]])
    let addressText = unwrap(addressContent.first?["text"])
    
    // Create the profile
    let profileRequest = JSONRPCRequest(
        id: 1,
        method: "tools/call",
        params: [
            "name": AnyCodable("createProfile"),
            "arguments": AnyCodable([
                "contact": contactText,
                "address": addressText,
                "interests": ["reading", "gaming", "coding"],
                "scores": [95, 88, 92],
                "ratings": [4.5, 4.8, 4.2],
                "activeStatuses": [true, false, true]
            ])
        ]
    )
    
    let profileResponse = unwrap(await client.send(profileRequest) as? JSONRPCResponse)
    
    #expect(profileResponse.id == 1)
    
    let profileResult = unwrap(profileResponse.result)
    let profileIsError = unwrap(profileResult["isError"]?.value as? Bool)
    #expect(profileIsError == false)
    
    let profileContent = unwrap(profileResult["content"]?.value as? [[String: String]])
    let profileText = unwrap(profileContent.first?["text"])
    
    // Verify the profile
    let profile = try JSONDecoder().decode(Profile.self, from: profileText.data(using: .utf8)!)
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
    let intRequest = JSONRPCRequest(
        id: 1,
        method: "tools/call",
        params: [
            "name": "processOptionalIntArray",
            "arguments": [:]
        ]
    )
    
    let intResponse = unwrap(await client.send(intRequest) as? JSONRPCResponse)
    let intResult = unwrap(intResponse.result)
    let intContent = unwrap(intResult["content"]?.value as? [[String: String]])
    let intText = unwrap(intContent.first?["text"])
    #expect(intText == "[]")
    
    // Test optional string array with nil
    let stringRequest = JSONRPCRequest(
        id: 1,
        method: "tools/call",
        params: [
            "name": AnyCodable("processOptionalStringArray"),
            "arguments": AnyCodable([:])
        ]
    )
    
    let stringResponse = unwrap(await client.send(stringRequest) as? JSONRPCResponse)
    let stringResult = unwrap(stringResponse.result)
    let stringContent = unwrap(stringResult["content"]?.value as? [[String: String]])
    let stringText = unwrap(stringContent.first?["text"])
    #expect(stringText == "[]")
    
    // Test optional contact array with nil
    let contactRequest = JSONRPCRequest(
        id: 1,
        method: "tools/call",
        params: [
            "name": AnyCodable("processOptionalContactArray"),
            "arguments": AnyCodable([:])
        ]
    )
    
    let contactResponse = unwrap(await client.send(contactRequest) as? JSONRPCResponse)
    let contactResult = unwrap(contactResponse.result)
    let contactContent = unwrap(contactResult["content"]?.value as? [[String: String]])
    let contactText = unwrap(contactContent.first?["text"])
    #expect(contactText == "[]")
} 
