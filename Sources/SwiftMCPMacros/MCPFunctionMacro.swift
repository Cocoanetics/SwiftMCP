import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftCompilerPlugin
import SwiftDiagnostics
import Foundation

// MARK: - Diagnostics

enum MCPFunctionDiagnostic: DiagnosticMessage {
    case onlyFunctions
    case missingDescription(functionName: String)

    var message: String {
        switch self {
        case .onlyFunctions:
            return "@MCPFunction can only be applied to functions"
        case .missingDescription(let functionName):
            return "Function '\(functionName)' is missing a description. Consider adding a documentation comment or providing a description parameter."
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
            return MessageID(domain: "MCPFunctionMacro", id: "onlyFunctions")
        case .missingDescription:
            return MessageID(domain: "MCPFunctionMacro", id: "missingDescription")
        }
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
        var hasExplicitDescription = false
        if let arguments = node.arguments?.as(LabeledExprListSyntax.self) {
            for argument in arguments {
                if argument.label?.text == "description", let stringLiteral = argument.expression.as(StringLiteralExprSyntax.self) {
                    // Extract the string value from the string literal
                    let stringValue = stringLiteral.segments.description
                    // Remove quotes and escape special characters for string interpolation
                    let cleanedValue = stringValue
                        .replacingOccurrences(of: "\"", with: "\\\"")
                    descriptionArg = "\"\(cleanedValue)\""
                    hasExplicitDescription = true
                    break
                }
            }
        }
        
        // If no description was provided in the attribute, try to extract it from the leading documentation comment
        var foundDescriptionInDocs = false
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
                        foundDescriptionInDocs = true
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
                                foundDescriptionInDocs = true
                                break
                            }
                        }
                    }
                }
            }
        }
        
        // Emit a warning if no description was found
        if !hasExplicitDescription && !foundDescriptionInDocs {
            let diagnostic = Diagnostic(node: node, message: MCPFunctionDiagnostic.missingDescription(functionName: functionName))
            context.diagnose(diagnostic)
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
            
            // Extract default value if present
            var defaultValue = "nil"
            if let defaultExpr = param.defaultValue?.value {
                // For simple literals, we can use their string representation
                if let intLiteral = defaultExpr.as(IntegerLiteralExprSyntax.self) {
                    defaultValue = intLiteral.description
                } else if let floatLiteral = defaultExpr.as(FloatLiteralExprSyntax.self) {
                    defaultValue = floatLiteral.description
                } else if let boolLiteral = defaultExpr.as(BooleanLiteralExprSyntax.self) {
                    defaultValue = boolLiteral.description
                } else if let stringLiteral = defaultExpr.as(StringLiteralExprSyntax.self) {
                    // For string literals, we need to wrap them in quotes
                    let stringValue = stringLiteral.segments.description
                        .replacingOccurrences(of: "\"", with: "\\\"")
                    defaultValue = "\"\(stringValue)\""
                } else {
                    // For more complex expressions, use the full syntax description
                    // This is a simplification and might not work for all cases
                    defaultValue = "\"\(defaultExpr.description)\""
                }
            }
            
            if !parameterString.isEmpty {
                parameterString += ", "
            }
            
            parameterString += "ParameterInfo(name: \"\(paramName)\", type: \"\(paramType)\", description: \(paramDescription), defaultValue: \(defaultValue))"
        }
        
        // Extract return type if it exists
        let returnTypeString: String
        if let returnType = funcDecl.signature.returnClause?.type.description.trimmingCharacters(in: .whitespacesAndNewlines) {
            returnTypeString = "\"\(returnType)\""
        } else {
            returnTypeString = "nil"
        }
        
        // Create a registration statement using string interpolation for simplicity
        let registrationDecl = """
        ///
        /// autogenerated
        let __metadata_\(functionName) = MCPFunctionMetadata(name: "\(functionName)", parameters: [\(parameterString)], returnType: \(returnTypeString),  description: \(descriptionArg))
        """
        
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
