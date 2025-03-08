import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftCompilerPlugin
import SwiftDiagnostics
import Foundation

// MARK: - Diagnostics

enum MCPFunctionDiagnostic: String, DiagnosticMessage {
    case onlyFunctions = "@MCPFunction can only be applied to functions"

    var message: String {
        return rawValue
    }

    var severity: DiagnosticSeverity {
        return .error
    }

    var diagnosticID: MessageID {
        MessageID(domain: "MCPFunctionMacro", id: rawValue)
    }
}

// MARK: - Plugin

@main
struct SwiftMCPPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        MCPFunctionMacro.self,
    ]
}

// MARK: - Macro Implementation

/// Implementation of the MCPFunction macro
public struct MCPFunctionMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // Handle function declarations
        guard let funcDecl = declaration.as(FunctionDeclSyntax.self) else {
            let diagnostic = Diagnostic(node: node, message: MCPFunctionDiagnostic.onlyFunctions)
            context.diagnose(diagnostic)
            return []
        }
        
        // Extract function name
        let functionName = funcDecl.name.text
        
        // Extract parameter information
        var parameters: [String] = []
        for param in funcDecl.signature.parameterClause.parameters {
            let paramName = param.firstName.text
            let paramType = param.type.description.trimmingCharacters(in: .whitespacesAndNewlines)
            
            parameters.append("""
                ("\(paramName)", "\(paramType)")
                """)
        }
        
        // Extract return type if it exists
        let returnTypeString: String
        if let returnType = funcDecl.signature.returnClause?.type.description.trimmingCharacters(in: .whitespacesAndNewlines) {
            returnTypeString = "\"\(returnType)\""
        } else {
            returnTypeString = "nil"
        }
        
        // Create a single registration expression that will be executed when the class is loaded
        let registrationDecl = """
        // Auto-generated registration for \(functionName)
        @MainActor
        class __Register_\(functionName) {
            // This will be executed when the class is loaded
            static let once: Void = {
                registerMCPFunction(
                    name: "\(functionName)",
                    parameters: [
                        \(parameters.joined(separator: ",\n                        "))
                    ],
                    returnType: \(returnTypeString)
                )
                return ()
            }()
            
            // Execute the registration when the file is loaded
            init() {
                _ = Self.once
            }
        }
        // Ensure registration happens immediately by creating an instance
        @MainActor let __Register_\(functionName) = __Register_\(functionName)()
        """
        
        return [DeclSyntax(stringLiteral: registrationDecl)]
    }
}
