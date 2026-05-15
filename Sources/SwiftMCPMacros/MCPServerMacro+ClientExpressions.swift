//
//  MCPServerMacro+ClientExpressions.swift
//  SwiftMCPMacros
//
//  Small helpers that produce call-site expressions and signature strings
//  for the generated `Client` methods.
//

import Foundation
import SwiftSyntax

extension MCPServerMacro {
    static func parameterSignature(_ parameter: ClientParameter) -> String {
        let label: String
        if parameter.label == "_" {
            label = "_ \(parameter.name)"
        } else if parameter.label != parameter.name {
            label = "\(parameter.label) \(parameter.name)"
        } else {
            label = parameter.name
        }

        var signature = "\(label): \(parameter.typeString)"
        if let defaultValue = parameter.defaultValue, !defaultValue.isEmpty {
            signature += " = \(defaultValue)"
        }
        return signature
    }

    static func effectSpecifiersString(isAsync: Bool, throwsKeyword: String?) -> String {
        var parts: [String] = []
        if isAsync {
            parts.append("async")
        }
        if let throwsKeyword {
            parts.append(throwsKeyword)
        }
        guard !parts.isEmpty else { return "" }
        return " " + parts.joined(separator: " ")
    }

    static func toolCallExpression(
        toolName: String,
        hasParameters: Bool,
        argumentsName: String,
        isAsync: Bool,
        isThrowing: Bool
    ) -> String {
        let call = hasParameters
            ? "proxy.callTool(\"\(toolName)\", arguments: \(argumentsName))"
            : "proxy.callTool(\"\(toolName)\")"

        let tryPrefix = isThrowing ? "try " : "try! "

        if isAsync {
            return "\(tryPrefix)await \(call)"
        }

        return "\(tryPrefix)MCPClientBlocking.call { try await \(call) }"
    }

    static func resourceReadExpression(
        isAsync: Bool,
        isThrowing: Bool
    ) -> String {
        let call = "proxy.readResource(uri: uri)"
        let tryPrefix = isThrowing ? "try " : "try! "

        if isAsync {
            return "\(tryPrefix)await \(call)"
        }

        return "\(tryPrefix)MCPClientBlocking.call { try await \(call) }"
    }

    static func promptCallExpression(
        promptName: String,
        hasParameters: Bool,
        argumentsName: String,
        isAsync: Bool,
        isThrowing: Bool
    ) -> String {
        let call = hasParameters
            ? "proxy.getPrompt(name: \"\(promptName)\", arguments: \(argumentsName))"
            : "proxy.getPrompt(name: \"\(promptName)\")"

        let tryPrefix = isThrowing ? "try " : "try! "

        if isAsync {
            return "\(tryPrefix)await \(call)"
        }

        return "\(tryPrefix)MCPClientBlocking.call { try await \(call) }"
    }

    static func resourceTemplates(from funcDecl: FunctionDeclSyntax) -> [String] {
        for attribute in funcDecl.attributes {
            guard let identifierAttr = attribute.as(AttributeSyntax.self),
                  let identifier = identifierAttr.attributeName.as(IdentifierTypeSyntax.self),
                  identifier.name.text == "MCPResource",
                  let argList = identifierAttr.arguments?.as(LabeledExprListSyntax.self) else {
                continue
            }

            var templates: [String] = []
            for arg in argList where arg.label == nil {
                if let stringLiteral = arg.expression.as(StringLiteralExprSyntax.self) {
                    templates.append(stringLiteral.segments.description)
                } else if let arrayExpr = arg.expression.as(ArrayExprSyntax.self) {
                    for element in arrayExpr.elements {
                        if let stringLiteral = element.expression.as(StringLiteralExprSyntax.self) {
                            templates.append(stringLiteral.segments.description)
                        }
                    }
                }
            }
            return templates
        }

        return []
    }

    static func resourceTemplateVariables(in template: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"\{[^}]+\}"#) else {
            return []
        }

        let nsRange = NSRange(template.startIndex..., in: template)
        let matches = regex.matches(in: template, range: nsRange)
        var variables: [String] = []

        for match in matches {
            guard let range = Range(match.range, in: template) else { continue }
            var expression = String(template[range].dropFirst().dropLast())

            if let first = expression.first, "+#./;?&".contains(first) {
                expression.removeFirst()
            }

            for spec in expression.split(separator: ",") {
                var name = String(spec)
                if let starIndex = name.firstIndex(of: "*") {
                    name = String(name[..<starIndex])
                }
                if let colonIndex = name.firstIndex(of: ":") {
                    name = String(name[..<colonIndex])
                }
                if !name.isEmpty, !variables.contains(name) {
                    variables.append(name)
                }
            }
        }

        return variables
    }
}
