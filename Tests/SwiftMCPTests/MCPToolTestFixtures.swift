import Foundation
@testable import SwiftMCP

// Test class with SchemaRepresentable types
@MCPServer
final class SchemaRepresentableTests {
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
final class EnumArrayTest {
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
final class SchemaRepresentableArrayTest {
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
