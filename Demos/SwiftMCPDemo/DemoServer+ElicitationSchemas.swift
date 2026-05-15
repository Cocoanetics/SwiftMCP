import Foundation
import SwiftMCP

extension DemoServer {

    // MARK: - Shared call logging

    static func logCall(function: String, arguments: [String: any Sendable] = [:]) async {
        var data: [String: any Sendable] = [
            "function": function,
            "message": "\(function) called"
        ]
        if !arguments.isEmpty {
            data["arguments"] = arguments
        }
        await Session.current?.sendLogNotification(LogMessage(level: .info, data: data))
    }

    static func message(for color: Color) -> String {
        switch color {
        case .red:
            return "You selected RED!"
        case .green:
            return "You selected GREEN!"
        case .blue:
            return "You selected BLUE!"
        }
    }
}

// Schema builders and response describers for DemoServer's elicitation
// tools. Static helpers live here so the actor body stays focused on
// tool dispatch.
extension DemoServer {

    // MARK: - Contact info

    static func makeContactInfoSchema() -> JSONSchema {
        .object(JSONSchema.Object(
            properties: [
                "name": .string(
                    title: "Full Name",
                    description: "Your full name",
                    format: nil,
                    minLength: 2,
                    maxLength: 50
                ),
                "email": .string(
                    title: "Email Address",
                    description: "Your email address",
                    format: "email",
                    minLength: nil,
                    maxLength: nil
                ),
                "age": .number(title: "Age", description: "Your age", minimum: 13, maximum: 120)
            ],
            required: ["name", "email"],
            title: "Contact Information",
            description: "Basic contact details"
        ))
    }

    static func describeContactResponse(_ response: ElicitationCreateResponse) -> String {
        switch response.action {
        case .accept:
            guard let content = response.content else {
                return "User accepted but no content was provided"
            }
            let name = content["name"]?.value as? String ?? "Unknown"
            let email = content["email"]?.value as? String ?? "Unknown"
            let age = content["age"]?.value as? Double ?? 0
            return "Thank you! Contact info received: \(name) (\(email)), age: \(Int(age))"
        case .decline:
            return "User declined to provide contact information"
        case .cancel:
            return "User cancelled the contact information request"
        }
    }

    // MARK: - Project preferences

    static func makeProjectPreferencesSchema() -> JSONSchema {
        .object(JSONSchema.Object(
            properties: [
                "projectType": .enum(values: ["web", "mobile", "desktop", "api"], description: "Type of project"),
                "framework": .string(description: "Preferred framework or technology"),
                "priority": .enum(values: ["speed", "cost", "quality"], description: "Main priority for the project"),
                "hasDeadline": .boolean(description: "Whether the project has a specific deadline")
            ],
            required: ["projectType", "priority"],
            description: "Project preferences and requirements"
        ))
    }

    static func describeProjectPreferencesResponse(_ response: ElicitationCreateResponse) -> String {
        switch response.action {
        case .accept:
            guard let content = response.content else {
                return "User accepted but no content was provided"
            }
            let projectType = content["projectType"]?.value as? String ?? "unspecified"
            let framework = content["framework"]?.value as? String ?? "not specified"
            let priority = content["priority"]?.value as? String ?? "unspecified"
            let hasDeadline = content["hasDeadline"]?.value as? Bool ?? false
            let base = "Project preferences received: \(projectType) project using "
                + "\(framework), prioritizing \(priority)"
            return base + (hasDeadline ? " with a deadline" : " without a specific deadline")
        case .decline:
            return "User declined to provide project preferences"
        case .cancel:
            return "User cancelled the project preferences request"
        }
    }

    // MARK: - User credentials

    static func makeUserCredentialsSchema() -> JSONSchema {
        .object(JSONSchema.Object(
            properties: [
                "username": .string(
                    title: "Username",
                    description: "Username (3-20 characters)",
                    format: nil,
                    minLength: 3,
                    maxLength: 20
                ),
                "password": .string(
                    title: "Password",
                    description: "Password (8-50 characters)",
                    format: nil,
                    minLength: 8,
                    maxLength: 50
                ),
                "confirmPassword": .string(
                    title: "Confirm Password",
                    description: "Confirm password",
                    format: nil,
                    minLength: 8,
                    maxLength: 50
                ),
                "email": .string(
                    title: "Email",
                    description: "Email address",
                    format: "email",
                    minLength: 5,
                    maxLength: 100
                ),
                "agreeToTerms": .boolean(
                    title: "Terms & Conditions",
                    description: "I agree to the terms and conditions",
                    defaultValue: false
                ),
                "receiveNewsletter": .boolean(
                    title: "Newsletter",
                    description: "Receive newsletter updates",
                    defaultValue: true
                )
            ],
            required: ["username", "password", "confirmPassword", "email", "agreeToTerms"],
            title: "Account Registration",
            description: "User credentials with validation constraints"
        ))
    }

    static func describeUserCredentialsResponse(_ response: ElicitationCreateResponse) -> String {
        switch response.action {
        case .accept:
            guard let content = response.content else {
                return "User accepted but no content was provided"
            }
            let username = content["username"]?.value as? String ?? "Unknown"
            let email = content["email"]?.value as? String ?? "Unknown"
            let password = content["password"]?.value as? String ?? ""
            let confirmPassword = content["confirmPassword"]?.value as? String ?? ""
            if password == confirmPassword {
                return "Account creation successful! Username: \(username), Email: \(email)"
            } else {
                return "Password mismatch detected. Please try again."
            }
        case .decline:
            return "User declined to create account"
        case .cancel:
            return "User cancelled the account creation"
        }
    }

    // MARK: - User preferences

    static func makeUserPreferencesSchema() -> JSONSchema {
        .object(JSONSchema.Object(
            properties: [
                "theme": .enum(
                    values: ["light", "dark", "auto"],
                    title: "Theme Preference",
                    description: "Choose your preferred theme",
                    enumNames: ["Light Mode", "Dark Mode", "Auto (System)"]
                ),
                "language": .enum(
                    values: ["en", "es", "fr", "de", "ja"],
                    title: "Language",
                    description: "Select your preferred language",
                    enumNames: ["English", "Español", "Français", "Deutsch", "日本語"]
                ),
                "notifications": .boolean(
                    title: "Enable Notifications",
                    description: "Receive push notifications",
                    defaultValue: true
                ),
                "maxItems": .number(
                    title: "Max Items per Page",
                    description: "Number of items to display per page",
                    minimum: 10,
                    maximum: 100
                )
            ],
            required: ["theme", "language"],
            title: "User Preferences",
            description: "Customize your application experience"
        ))
    }

    static func describeUserPreferencesResponse(_ response: ElicitationCreateResponse) -> String {
        switch response.action {
        case .accept:
            guard let content = response.content else {
                return "User accepted but no content was provided"
            }
            let theme = content["theme"]?.value as? String ?? "unknown"
            let language = content["language"]?.value as? String ?? "unknown"
            let notifications = content["notifications"]?.value as? Bool ?? false
            let maxItems = content["maxItems"]?.value as? Double ?? 25.0
            return "Preferences saved! Theme: \(theme), Language: \(language), "
                + "Notifications: \(notifications), Max items: \(Int(maxItems))"
        case .decline:
            return "User declined to set preferences"
        case .cancel:
            return "User cancelled preference configuration"
        }
    }
}
