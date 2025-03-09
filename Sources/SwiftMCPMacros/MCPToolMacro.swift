//
//  MCPToolMacro.swift
//  SwiftMCPMacros
//
//  Created by Oliver Drobnik on 08.03.25.
//

import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/**
 Implementation of the MCPTool macro.
 
 This macro adds a `mcpTools` computed property to a class or struct,
 which returns an array of all MCP tools defined in that type.
 */
public struct MCPToolMacro: MemberMacro {
    /**
     Expands the macro to provide additional members for the declaration.
     
     - Parameters:
       - node: The attribute syntax node
       - declaration: The declaration syntax
       - context: The macro expansion context
     
     - Returns: An array of member declaration syntax nodes
     */
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // Find all functions with the MCPFunction macro
        var mcpFunctions: [String] = []
        
        for member in declaration.memberBlock.members {
            if let funcDecl = member.decl.as(FunctionDeclSyntax.self) {
                // Check if the function has the MCPFunction macro
                for attribute in funcDecl.attributes {
                    if let identifierAttr = attribute.as(AttributeSyntax.self),
                       let identifier = identifierAttr.attributeName.as(IdentifierTypeSyntax.self),
                       identifier.name.text == "MCPFunction" {
                        mcpFunctions.append(funcDecl.name.text)
                        break
                    }
                }
            }
        }
        
        // Create a computed property that returns an array of MCPTool objects
        let mcpToolsProperty = """
        /// Returns an array of all MCP tools defined in this type
        var mcpTools: [MCPTool] {
            let mirror = Mirror(reflecting: self)
            var tools: [MCPTool] = []
            
            for child in mirror.children {
                if let metadata = child.value as? MCPFunctionMetadata,
                   child.label?.hasPrefix("__metadata_") == true {
                    let functionName = String(child.label!.dropFirst("__metadata_".count))
                    
                    // Create a JSON schema from the function metadata
                    let schema = JSONSchema.object(
                        properties: Dictionary(uniqueKeysWithValues: metadata.parameters.map { param in
                            let schemaType: JSONSchema
                            switch param.type {
                            case "Int", "Double", "Float", "CGFloat":
                                schemaType = .number(description: param.description)
                            case "Bool":
                                schemaType = .boolean(description: param.description)
                            case let arrayType where arrayType.hasPrefix("[") && arrayType.hasSuffix("]"):
                                // Handle array types
                                let elementType = String(arrayType.dropFirst().dropLast())
                                let itemSchema: JSONSchema
                                switch elementType {
                                case "Int", "Double", "Float", "CGFloat":
                                    itemSchema = .number(description: nil)
                                case "Bool":
                                    itemSchema = .boolean(description: nil)
                                default:
                                    itemSchema = .string(description: nil)
                                }
                                schemaType = .array(items: itemSchema, description: param.description)
                            default:
                                schemaType = .string(description: param.description)
                            }
                            return (param.name, schemaType)
                        }),
                        required: metadata.parameters.filter { $0.defaultValue == nil }.map { $0.name }
                    )
                    
                    let tool = MCPTool(
                        name: functionName,
                        description: metadata.description,
                        inputSchema: schema
                    )
                    tools.append(tool)
                }
            }
            
            return tools
        }
        """
        
        // Create a dictionary property that maps function names to their wrapper methods
        var handlersInitLines: [String] = []
        for funcName in mcpFunctions {
            handlersInitLines.append("            handlers[\"\(funcName)\"] = self.__call_\(funcName)")
        }
        
        // Create a callTool method that uses a switch statement to call the appropriate wrapper function
        var switchCases: [String] = []
        for funcName in mcpFunctions {
            switchCases.append("""
            case "\(funcName)":
                guard let result = __call_\(funcName)(enrichedArguments) else {
                    throw MCPToolError.callFailed(name: name, reason: "Function call returned nil")
                }
                return result
            """)
        }
        
        let callToolMethod = """
        /// Calls a tool by name with the provided arguments
        /// - Parameters:
        ///   - name: The name of the tool to call
        ///   - arguments: A dictionary of arguments to pass to the tool
        /// - Returns: The result of the tool call
        /// - Throws: MCPToolError if the tool doesn't exist or cannot be called
        func callTool(_ name: String, arguments: [String: Any]) throws -> Any {
            // Find the tool by name
            guard let tool = mcpTools.first(where: { $0.name == name }) else {
                throw MCPToolError.unknownTool(name: name)
            }
            
            // Enrich arguments with default values
            let enrichedArguments = tool.enrichArguments(arguments, forObject: self, functionName: name)
            
            // Call the appropriate wrapper method based on the tool name
            switch name {
            \(switchCases.joined(separator: "\n"))
            default: throw MCPToolError.unknownTool(name: name)
            }
        }
        """
        
        return [
            DeclSyntax(stringLiteral: mcpToolsProperty),
            DeclSyntax(stringLiteral: callToolMethod)
        ]
    }
} 
