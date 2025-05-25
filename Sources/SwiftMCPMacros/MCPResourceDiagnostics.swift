import Foundation
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Diagnostic messages for the `MCPResource` macro.
enum MCPResourceDiagnostic: DiagnosticMessage {
    case onlyFunctions
    case requiresStringLiteral
    case missingParameterForPlaceholder(placeholder: String) // E001
    case unknownPlaceholder(parameterName: String) // E002
    case optionalParameterNeedsDefault(paramName: String) // E003

    var message: String {
        switch self {
        case .onlyFunctions:
            return "The MCPResource macro can only be applied to functions"
        case .requiresStringLiteral:
            return "The MCPResource macro requires a string literal argument"
        case .missingParameterForPlaceholder(let ph):
            return "Missing parameter for placeholder '{\(ph)}'"
        case .unknownPlaceholder(let name):
            return "Unknown placeholder '{\(name)}' – not present in template"
        case .optionalParameterNeedsDefault(let name):
            return "Optional parameter '\(name)' requires a default value"
        }
    }

    var severity: DiagnosticSeverity { .error }

    var diagnosticID: MessageID {
        switch self {
        case .missingParameterForPlaceholder:
            return MessageID(domain: "SwiftMCP", id: "E001")
        case .unknownPlaceholder:
            return MessageID(domain: "SwiftMCP", id: "E002")
        case .optionalParameterNeedsDefault:
            return MessageID(domain: "SwiftMCP", id: "E003")
        case .onlyFunctions:
            return MessageID(domain: "SwiftMCP", id: "OnlyFunctions")
        case .requiresStringLiteral:
            return MessageID(domain: "SwiftMCP", id: "RequiresStringLiteral")
        }
    }
}
