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
        
        // Create a dictionary property that maps function names to their wrapper methods
        var handlersInitLines: [String] = []
        for funcName in mcpFunctions {
            handlersInitLines.append("            handlers[\"\(funcName)\"] = self.__call_\(funcName)")
        }
        
        let functionHandlersProperty = """
        /// Dictionary of function handlers for all MCP functions
        lazy var functionHandlers: [String: ([String: Any]) -> Any?] = {
            var handlers: [String: ([String: Any]) -> Any?] = [:]
            \(handlersInitLines.joined(separator: "\n"))
            return handlers
        }()
        """
        
        // Create a callTool method that uses a switch statement to call the appropriate wrapper function
        var switchCases: [String] = []
        for funcName in mcpFunctions {
            switchCases.append("            case \"\(funcName)\": return __call_\(funcName)(arguments)")
        }
        
        let callToolMethod = """
        /// Calls a tool by name with the provided arguments
        /// - Parameters:
        ///   - name: The name of the tool to call
        ///   - arguments: A dictionary of arguments to pass to the tool
        /// - Returns: The result of the tool call, or nil if the tool could not be called
        func callTool(_ name: String, arguments: [String: Any]) -> Any? {
            switch name {
            \(switchCases.joined(separator: "\n"))
            default: return "Error: Unknown tool '\\(name)'"
            }
        }
        """
        
        return [
            DeclSyntax(stringLiteral: mcpToolsProperty),
            DeclSyntax(stringLiteral: callToolMethod)
        ]
    }
} 
