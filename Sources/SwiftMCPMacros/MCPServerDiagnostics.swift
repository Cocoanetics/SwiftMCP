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
	case requiresReferenceType(typeName: String)
	
	var message: String {
		switch self {
			case .requiresReferenceType(let typeName):
				return "'\(typeName)' must be a reference type (class or actor)"
		}
	}
	
	var severity: DiagnosticSeverity {
		switch self {
			case .requiresReferenceType:
				return .error
		}
	}
	
	var diagnosticID: MessageID {
		switch self {
			case .requiresReferenceType:
				return MessageID(domain: "SwiftMCPMacros", id: "RequiresReferenceType")
		}
	}
}

/// Fix-it messages for the MCPServer macro
enum MCPServerFixItMessage: FixItMessage {
	case replaceWithClass(keyword: String)
	
	var message: String {
		switch self {
			case .replaceWithClass(let keyword):
				return "Change '\(keyword)' to 'class'"
		}
	}
	
	var fixItID: MessageID {
		switch self {
			case .replaceWithClass:
				return MessageID(domain: "SwiftMCPMacros", id: "ReplaceWithClass")
		}
	}
} 
