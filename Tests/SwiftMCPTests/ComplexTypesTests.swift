import Foundation
import Testing
@testable import SwiftMCP

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

/// Wrapper used when array outputs are boxed to support outputSchema.
struct ContactInfoArrayOutput: Sendable, Codable {
    let items: [ContactInfo]
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
    func createContact(
        name: String,
        email: String,
        phone: String,
        age: Int = 30,
        isActive: Bool = true
    ) -> ContactInfo {
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
    func createProfile(
        contact: ContactInfo,
        address: Address,
        interests: [String] = [],
        scores: [Int] = [],
        ratings: [Double] = [],
        activeStatuses: [Bool] = []
    ) -> Profile {
        return Profile(
            contact: contact,
            address: address,
            interests: interests,
            scores: scores,
            ratings: ratings,
            activeStatuses: activeStatuses
        )
    }
}

// Tests live in ComplexTypesArrayTests.swift and ComplexTypesObjectTests.swift
