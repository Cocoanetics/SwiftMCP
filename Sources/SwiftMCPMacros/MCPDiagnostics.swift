//
//  MCPDiagnostics.swift
//  SwiftMCPMacros
//
//  Created by Oliver Drobnik on 08.03.25.
//

import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics
import Foundation
import SwiftMCP

/**
 Diagnostic messages for the MCP macros.
 
 This enum defines the diagnostic messages that can be emitted by the MCP macros,
 including errors and warnings related to function declarations.
 */
enum MCPFunctionDiagnostic: DiagnosticMessage {
    /// Error when the macro is applied to a non-function declaration
    case onlyFunctions
    
    /// Warning when a function is missing a description
    case missingDescription(functionName: String)

    var message: String {
        switch self {
        case .onlyFunctions:
            return "The @MCPFunction macro can only be applied to functions"
        case .missingDescription(let functionName):
            return "Function '\(functionName)' is missing a description. Add a documentation comment or provide a description parameter."
        }
    }

    var severity: DiagnosticSeverity {
        switch self {
        case .onlyFunctions:
            return .error
        case .missingDescription:
            return .warning
        }
    }

    var diagnosticID: MessageID {
        switch self {
        case .onlyFunctions:
            return MessageID(domain: "SwiftMCP", id: "onlyFunctions")
        case .missingDescription:
            return MessageID(domain: "SwiftMCP", id: "missingDescription")
        }
    }
} 