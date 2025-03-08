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
        MCPToolMacro.self,
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
        
        // Extract description from the attribute if provided
        var descriptionArg = "nil"
        if let arguments = node.arguments?.as(LabeledExprListSyntax.self) {
            for argument in arguments {
                if argument.label?.text == "description", let stringLiteral = argument.expression.as(StringLiteralExprSyntax.self) {
                    // Extract the string value from the string literal
                    let stringValue = stringLiteral.segments.description
                    // Remove quotes and escape special characters for string interpolation
                    let cleanedValue = stringValue
                        .replacingOccurrences(of: "\"", with: "\\\"")
                    descriptionArg = "\"\(cleanedValue)\""
                    break
                }
            }
        }
        
        // If no description was provided in the attribute, try to extract it from the leading documentation comment
        if descriptionArg == "nil" {
            let leadingTrivia = funcDecl.leadingTrivia.description
            
            // Extract the function description from Swift's standard documentation styles
            var foundDescription = false
            
            // 1. Check for /// style comments (Swift's preferred style)
            let docLines = leadingTrivia.split(separator: "\n")
            
            // First try to find /// style comments
            for line in docLines {
                let trimmedLine = line.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                if trimmedLine.hasPrefix("///") && 
                   !trimmedLine.contains("- Parameter") && 
                   !trimmedLine.contains("- Returns") {
                    // Extract the description (remove the /// prefix and trim whitespace)
                    let description = trimmedLine.dropFirst(3).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                    if !description.isEmpty {
                        descriptionArg = "\"\(description.replacingOccurrences(of: "\"", with: "\\\""))\""
                        foundDescription = true
                        break
                    }
                }
            }
            
            // 2. If no description found, check for /** */ style comments (Swift's multi-line doc style)
            if !foundDescription {
                // Use regex to extract content between /** and */
                let multilineRegex = try? NSRegularExpression(pattern: "/\\*\\*(.*?)\\*/", options: [.dotMatchesLineSeparators])
                if let multilineRegex = multilineRegex {
                    let nsString = leadingTrivia as NSString
                    let matches = multilineRegex.matches(in: leadingTrivia, options: [], range: NSRange(location: 0, length: nsString.length))
                    
                    if let match = matches.first, match.numberOfRanges >= 2 {
                        let docBlock = nsString.substring(with: match.range(at: 1))
                        
                        // Split the doc block into lines and find the first non-empty line that's not a parameter or return description
                        let blockLines = docBlock.split(separator: "\n")
                        for line in blockLines {
                            let trimmedLine = line.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                            // Skip empty lines, parameter descriptions, and return descriptions
                            if !trimmedLine.isEmpty && 
                               !trimmedLine.contains("- Parameter") && 
                               !trimmedLine.contains("- Returns") {
                                descriptionArg = "\"\(trimmedLine.replacingOccurrences(of: "\"", with: "\\\""))\""
                                foundDescription = true
                                break
                            }
                        }
                    }
                }
            }
        }
        
        // Extract parameter descriptions from leading trivia (documentation comments)
        var paramDescriptions: [String: String] = [:]
        let leadingTrivia = funcDecl.leadingTrivia.description
        
        // Use regex to find parameter descriptions in Swift's standard format
        
        // Swift-style: "- Parameter name: description"
        let swiftParamRegex = try? NSRegularExpression(pattern: "- Parameter (\\w+):\\s*(.*)", options: [])
        if let regex = swiftParamRegex {
            let nsString = leadingTrivia as NSString
            let matches = regex.matches(in: leadingTrivia, options: [], range: NSRange(location: 0, length: nsString.length))
            
            for match in matches {
                if match.numberOfRanges >= 3 {
                    let paramName = nsString.substring(with: match.range(at: 1))
                    let paramDesc = nsString.substring(with: match.range(at: 2)).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                    paramDescriptions[paramName] = paramDesc
                }
            }
        }
        
        // Extract parameter information
        var parameterString = ""
        for param in funcDecl.signature.parameterClause.parameters {
            let paramName = param.firstName.text
            let paramType = param.type.description.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Get parameter description from trivia or from MCPParameterDescription attribute
            var paramDescription = "nil"
            
            // First check if we have a description from the documentation comments
            if let docDescription = paramDescriptions[paramName] {
                paramDescription = "\"\(docDescription.replacingOccurrences(of: "\"", with: "\\\""))\""
            }
            
            // Then check for MCPParameterDescription attribute (this will override doc comments if both exist)
            for attribute in param.attributes {
                if let attributeIdent = attribute.as(AttributeSyntax.self)?.attributeName.as(IdentifierTypeSyntax.self),
                   attributeIdent.name.text == "MCPParameterDescription",
                   let arguments = attribute.as(AttributeSyntax.self)?.arguments?.as(LabeledExprListSyntax.self),
                   let firstArg = arguments.first?.expression.as(StringLiteralExprSyntax.self) {
                    let descriptionValue = firstArg.segments.description
                    // Clean up the description string
                    let cleanedValue = descriptionValue
                        .replacingOccurrences(of: "\"", with: "\\\"")
                    paramDescription = "\"\(cleanedValue)\""
                    break
                }
            }
            
            if !parameterString.isEmpty {
                parameterString += ", "
            }
            
            parameterString += "ParameterInfo(name: \"\(paramName)\", type: \"\(paramType)\", description: \(paramDescription))"
        }
        
        // Extract return type if it exists
        let returnTypeString: String
        if let returnType = funcDecl.signature.returnClause?.type.description.trimmingCharacters(in: .whitespacesAndNewlines) {
            returnTypeString = "\"\(returnType)\""
        } else {
            returnTypeString = "nil"
        }
        
        // Create a registration function that will be called when the class is loaded
        let registrationDecl = """
        ///
        /// autogenerated
        let __metadata_\(functionName) = MCPFunctionMetadata(name: "\(functionName)", parameters: [\(parameterString)], returnType: \(returnTypeString),  description: \(descriptionArg))
        """
		
		/*
		 // Auto-generated registration for \(functionName)
		 @MainActor
		 class __metadata_\(functionName) {
			 // This will be executed when the class is loaded
			 static let once: Void = {
				 registerMCPFunction(
					 name: "\(functionName)",
					 parameters: [
						 \(parameters.joined(separator: ",\n                        "))
					 ],
					 returnType: \(returnTypeString),
					 description: \(descriptionArg)
				 )
				 return ()
			 }()
			 
			 // Execute the registration when the file is loaded
			 init() {
				 _ = Self.once
			 }
		 }
		 // Ensure registration happens immediately by creating an instance
		 */
		
		
//		public struct MCPFunctionMetadata: Codable
//		{
//			public struct ParameterMeta: Codable {
//				public let name: String
//				public let type: String
//			}
//			
//			public let name: String
//			
//			public let parameters: [ParameterMeta]
//			
//			public let returnType: String
//			
//			public let description: String?
//		}
        
        return [DeclSyntax(stringLiteral: registrationDecl)]
    }
}

/// Implementation of the MCPTool macro
public struct MCPToolMacro: MemberMacro {
	public static func expansion(
		of node: AttributeSyntax,
		providingMembersOf declaration: some DeclGroupSyntax,
		in context: some MacroExpansionContext
	) throws -> [DeclSyntax] {
		// Create a mcpTools computed property that returns the registered functions
		let mcpToolsProperty = """
		/// Returns an array of all MCP Tools
		var mcpTools: [MCPTool] {
			let mirror = Mirror(reflecting: self)
			let metadata: [MCPFunctionMetadata] = mirror.children.compactMap { child in
				guard let label = child.label, label.hasPrefix("__metadata_") else { return nil }
				return child.value as? MCPFunctionMetadata
			}

			return metadata.convertedToTools()
		}
		"""
		return [DeclSyntax(stringLiteral: mcpToolsProperty)]
	}
}
