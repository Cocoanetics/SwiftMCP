//
//  MCPDiagnostics.swift
//  SwiftMCPMacros
//
//  Created by Oliver Drobnik on 08.03.25.
//

import Foundation
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/**
 Diagnostic messages for the MCP macros.
 
 This enum defines the diagnostic messages that can be emitted by the MCP macros,
 including errors and warnings related to function declarations.
 */
enum MCPToolDiagnostic: DiagnosticMessage {
    /// Error when the macro is applied to a non-function declaration
    case onlyFunctions
    
    /// Warning when a function is missing a description
    case missingDescription(functionName: String)
    
    /// Error when a parameter has an unsupported default value type
    case invalidDefaultValueType(paramName: String, typeName: String)
    
    /// Error when a parameter has an unsupported closure type
    case closureTypeNotSupported(paramName: String, typeName: String)

    var message: String {
        switch self {
        case .onlyFunctions:
            return "The MCPTool macro can only be applied to functions"
        case .missingDescription(let functionName):
            return "Function '\(functionName)' is missing a description. Add a documentation comment or provide a description parameter."
        case .invalidDefaultValueType(let paramName, let typeName):
            return "Parameter '\(paramName)' has an unsupported default value type '\(typeName)'. Only numbers, booleans, and strings are supported."
        case .closureTypeNotSupported(let paramName, let typeName):
            return "Parameter '\(paramName)' has an unsupported closure type '\(typeName)'. Closures are not supported in MCP tools."
        }
    }

    var severity: DiagnosticSeverity {
        switch self {
        case .onlyFunctions, .invalidDefaultValueType, .closureTypeNotSupported:
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
        case .invalidDefaultValueType:
            return MessageID(domain: "SwiftMCP", id: "invalidDefaultValueType")
        case .closureTypeNotSupported:
            return MessageID(domain: "SwiftMCP", id: "closureTypeNotSupported")
        }
    }
} 
