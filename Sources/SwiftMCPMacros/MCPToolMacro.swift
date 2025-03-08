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
                            (param.name, JSONSchema.string(description: param.description))
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
        
        return [DeclSyntax(stringLiteral: mcpToolsProperty)]
    }
} 
