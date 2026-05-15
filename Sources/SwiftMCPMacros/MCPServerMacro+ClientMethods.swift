//
//  MCPServerMacro+ClientMethods.swift
//  SwiftMCPMacros
//
//  Per-method line emitters used by `makeClientType` to generate tool,
//  resource, and prompt method bodies on the nested `Client` struct.
//

import Foundation
import SwiftSyntax

extension MCPServerMacro {
    static func makeClientMethodLines(metadata: ClientFunctionMetadata, wireToolName: String? = nil) -> [String] {
        var lines: [String] = []
        lines.append(contentsOf: docCommentLines(for: metadata))

        for attribute in metadata.propagatedAttributes {
            lines.append("    \(attribute)")
        }

        let signature = metadata.parameters.map { parameterSignature($0) }.joined(separator: ", ")
        let effectSpecifiers = effectSpecifiersString(isAsync: metadata.isAsync, throwsKeyword: metadata.throwsKeyword)
        let hasParameters = !metadata.parameters.isEmpty

        switch metadata.kind {
        case .tool:
            lines.append(contentsOf: toolMethodBodyLines(
                metadata: metadata,
                signature: signature,
                effectSpecifiers: effectSpecifiers,
                hasParameters: hasParameters,
                wireToolName: wireToolName
            ))

        case .resource(let templates):
            lines.append(contentsOf: resourceMethodBodyLines(
                metadata: metadata,
                signature: signature,
                effectSpecifiers: effectSpecifiers,
                hasParameters: hasParameters,
                templates: templates
            ))

        case .prompt:
            lines.append(contentsOf: promptMethodBodyLines(
                metadata: metadata,
                signature: signature,
                effectSpecifiers: effectSpecifiers,
                hasParameters: hasParameters
            ))
        }

        lines.append("    }")
        return lines
    }

    static func toolMethodBodyLines(
        metadata: ClientFunctionMetadata,
        signature: String,
        effectSpecifiers: String,
        hasParameters: Bool,
        wireToolName: String?
    ) -> [String] {
        var lines: [String] = []
        // Use .MCPClientReturn for all return types. For most types this resolves to Self
        // (via extension Decodable). For @Schema single-array wrapper structs it resolves
        // to [Element], so the generated proxy returns the unwrapped array automatically.
        let clientReturnType = metadata.hasReturnClause ? "\(metadata.returnTypeString).MCPClientReturn" : nil
        let returnClause = clientReturnType.map { " -> \($0)" } ?? ""

        lines.append("    public func \(metadata.name)(\(signature))\(effectSpecifiers)\(returnClause) {")
        lines.append(contentsOf: encodedArgumentLines(for: metadata.parameters, variableName: "arguments", indent: "        "))

        let argumentsName = (hasParameters && !metadata.isAsync) ? "capturedArguments" : "arguments"
        if hasParameters && !metadata.isAsync {
            lines.append("        let capturedArguments = arguments")
        }

        let callExpression = toolCallExpression(
            toolName: wireToolName ?? metadata.name,
            hasParameters: hasParameters,
            argumentsName: argumentsName,
            isAsync: metadata.isAsync,
            isThrowing: metadata.isThrowing
        )
        lines.append("        let text = \(callExpression)")

        if metadata.hasReturnClause, let clientReturnType {
            lines.append("        return try MCPClientResultDecoder.decode(\(clientReturnType).self, from: text)")
        } else if metadata.hasReturnClause {
            lines.append("        return try MCPClientResultDecoder.decode(\(metadata.returnTypeString).self, from: text)")
        } else {
            lines.append("        _ = try MCPClientResultDecoder.decode(Void.self, from: text)")
            lines.append("        return")
        }
        return lines
    }

    static func resourceMethodBodyLines(
        metadata: ClientFunctionMetadata,
        signature: String,
        effectSpecifiers: String,
        hasParameters: Bool,
        templates: [String]
    ) -> [String] {
        var lines: [String] = []
        let clientReturnType = metadata.hasReturnClause ? "\(metadata.returnTypeString).MCPClientReturn" : nil
        let returnClause = clientReturnType.map { " -> \($0)" } ?? ""

        lines.append("    public func \(metadata.name)(\(signature))\(effectSpecifiers)\(returnClause) {")
        lines.append(contentsOf: encodedArgumentLines(for: metadata.parameters, variableName: "arguments", indent: "        "))

        let argumentsName = hasParameters ? ((metadata.isAsync ? "arguments" : "capturedArguments")) : "[:]"
        if hasParameters && !metadata.isAsync {
            lines.append("        let capturedArguments = arguments")
        }

        let orderedTemplates = templates.sorted {
            let lhsCount = resourceTemplateVariables(in: $0).count
            let rhsCount = resourceTemplateVariables(in: $1).count
            if lhsCount == rhsCount { return $0 < $1 }
            return lhsCount > rhsCount
        }

        lines.append(contentsOf: resourceTemplateSelectionLines(
            metadata: metadata,
            orderedTemplates: orderedTemplates,
            argumentsName: argumentsName
        ))
        lines.append("        let contents = \(resourceReadExpression(isAsync: metadata.isAsync, isThrowing: metadata.isThrowing))")

        lines.append(contentsOf: resourceReturnLines(metadata: metadata, clientReturnType: clientReturnType))
        return lines
    }

    static func resourceTemplateSelectionLines(
        metadata: ClientFunctionMetadata,
        orderedTemplates: [String],
        argumentsName: String
    ) -> [String] {
        var lines: [String] = []
        if orderedTemplates.count == 1, let template = orderedTemplates.first {
            lines.append("        let uri = try \"\(template.escapedForSwiftString)\".constructURI(with: \(argumentsName))")
        } else {
            lines.append("        let uri: URL")
            for (index, template) in orderedTemplates.enumerated() {
                let variables = resourceTemplateVariables(in: template)
                let condition = variables.isEmpty
                    ? "true"
                    : variables.map { "\(argumentsName)[\"\($0)\"] != nil" }.joined(separator: " && ")
                let keyword = index == 0 ? "if" : "else if"
                lines.append("        \(keyword) \(condition) {")
                lines.append("            uri = try \"\(template.escapedForSwiftString)\".constructURI(with: \(argumentsName))")
                lines.append("        }")
            }
            lines.append("        else {")
            lines.append("            throw MCPServerProxyError.communicationError(\"No resource template matched for \(metadata.name)\")")
            lines.append("        }")
        }
        return lines
    }

    static func resourceReturnLines(
        metadata: ClientFunctionMetadata,
        clientReturnType: String?
    ) -> [String] {
        var lines: [String] = []
        if !metadata.hasReturnClause || metadata.returnTypeString == "Void" {
            lines.append("        return")
        } else if metadata.returnTypeString == "MCPResourceContent" || metadata.returnTypeString == "GenericResourceContent" {
            lines.append("        guard let content = contents.first else {")
            lines.append("            throw MCPServerProxyError.communicationError(\"Resource \(metadata.name) returned no content\")")
            lines.append("        }")
            lines.append("        return content")
        } else if metadata.returnTypeString == "[MCPResourceContent]" || metadata.returnTypeString == "[GenericResourceContent]" {
            lines.append("        return contents")
        } else if metadata.returnTypeString == "Data" {
            lines.append("        if let blob = contents.first?.blob {")
            lines.append("            return blob")
            lines.append("        }")
            lines.append("        if let text = contents.first?.text {")
            lines.append("            return try MCPClientResultDecoder.decode(Data.self, from: text)")
            lines.append("        }")
            lines.append("        throw MCPServerProxyError.communicationError(\"Resource \(metadata.name) returned no blob content\")")
        } else {
            lines.append("        guard let text = contents.first?.text else {")
            lines.append("            throw MCPServerProxyError.communicationError(\"Resource \(metadata.name) returned no text content\")")
            lines.append("        }")
            if let clientReturnType {
                lines.append("        return try MCPClientResultDecoder.decode(\(clientReturnType).self, from: text)")
            } else {
                lines.append("        return try MCPClientResultDecoder.decode(\(metadata.returnTypeString).self, from: text)")
            }
        }
        return lines
    }

    static func promptMethodBodyLines(
        metadata: ClientFunctionMetadata,
        signature: String,
        effectSpecifiers: String,
        hasParameters: Bool
    ) -> [String] {
        var lines: [String] = []
        lines.append("    public func \(metadata.name)(\(signature))\(effectSpecifiers) -> PromptResult {")
        lines.append(contentsOf: encodedArgumentLines(for: metadata.parameters, variableName: "arguments", indent: "        "))

        let argumentsName = (hasParameters && !metadata.isAsync) ? "capturedArguments" : "arguments"
        if hasParameters && !metadata.isAsync {
            lines.append("        let capturedArguments = arguments")
        }

        let callExpression = promptCallExpression(
            promptName: metadata.name,
            hasParameters: hasParameters,
            argumentsName: argumentsName,
            isAsync: metadata.isAsync,
            isThrowing: metadata.isThrowing
        )
        lines.append("        return \(callExpression)")
        return lines
    }
}
