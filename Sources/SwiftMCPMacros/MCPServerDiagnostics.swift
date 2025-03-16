import Foundation
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/**
 Diagnostic messages for the MCPServer macro.
 
 This enum defines the diagnostic messages that can be emitted by the MCPServer macro,
 including errors and warnings related to server declarations.
 */
enum MCPServerDiagnostic: DiagnosticMessage {
	/// Error when the macro is applied to a non-class declaration
	case requiresClass(typeName: String, actualType: String)
	
	var message: String {
		switch self {
			case .requiresClass(let typeName, let actualType):
				return "MCPServer can only be applied to classes, but '\(typeName)' is a \(actualType)"
		}
	}
	
	var severity: DiagnosticSeverity {
		switch self {
			case .requiresClass:
				return .error
		}
	}
	
	var diagnosticID: MessageID {
		switch self {
			case .requiresClass:
				return MessageID(domain: "SwiftMCP", id: "requiresClass")
		}
	}
}

/// Fix-it messages for the MCPServer macro
enum MCPServerFixItMessage: FixItMessage {
	case replaceWithClass(keyword: String)
	
	var message: String {
		switch self {
			case .replaceWithClass(let keyword):
				return "Replace '\(keyword)' with 'class'"
		}
	}
	
	var fixItID: MessageID {
		switch self {
			case .replaceWithClass:
				return MessageID(domain: "SwiftMCP", id: "replaceWithClass")
		}
	}
} 
