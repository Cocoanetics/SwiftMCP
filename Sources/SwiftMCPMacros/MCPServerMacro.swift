//
//  MCPServerMacro.swift
//  SwiftMCPMacros
//
//  Created by Oliver Drobnik on 08.03.25.
//

import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/**
 Implementation of the MCPServer macro.
 
 This macro adds a `mcpTools` computed property to a class or struct,
 which returns an array of all MCP tools defined in that type.
 */
public struct MCPServerMacro: MemberMacro {
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
        // Find all functions with the MCPTool macro
        var mcpTools: [String] = []
        
        for member in declaration.memberBlock.members {
            if let funcDecl = member.decl.as(FunctionDeclSyntax.self) {
                // Check if the function has the MCPTool macro
                for attribute in funcDecl.attributes {
                    if let identifierAttr = attribute.as(AttributeSyntax.self),
                       let identifier = identifierAttr.attributeName.as(IdentifierTypeSyntax.self),
                       identifier.name.text == "MCPTool" {
                        mcpTools.append(funcDecl.name.text)
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
            var metadataArray: [MCPToolMetadata] = []
            
            for child in mirror.children {
                if let metadata = child.value as? MCPToolMetadata,
                   child.label?.hasPrefix("__metadata_") == true {
                    metadataArray.append(metadata)
                }
            }
            
            return metadataArray.convertedToTools()
        }
        """
        
        // Create a dictionary property that maps function names to their wrapper methods
        var handlersInitLines: [String] = []
        for funcName in mcpTools {
            handlersInitLines.append("            handlers[\"\(funcName)\"] = self.__call_\(funcName)")
        }
        
        // Create a callTool method that uses a switch statement to call the appropriate wrapper function
        var switchCases: [String] = []
        for funcName in mcpTools {
            switchCases.append("""
            case "\(funcName)":
                return try __call_\(funcName)(enrichedArguments)
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
