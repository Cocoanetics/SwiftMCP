//
//  Visitor.swift
//  SwiftMCPAggregatorTool
//
//  SwiftSyntax visitor that collects `@MCPTool`, `@MCPResource`, and
//  `@MCPPrompt` methods from any extension marked with `@MCPExtension`.
//

import Foundation
import SwiftSyntax

final class ExtensionFinder: SyntaxVisitor {
    var byExtendedType: [String: [DiscoveredMethod]] = [:]
    var imports: Set<String> = []
    var currentFilePath: String = ""

    private var ifConfigStack: [String] = []

    override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
        let path = node.path.map { $0.name.text }.joined(separator: ".")
        if !path.isEmpty { imports.insert(path) }
        return .skipChildren
    }

    override func visit(_ node: IfConfigClauseSyntax) -> SyntaxVisitorContinueKind {
        if node.poundKeyword.tokenKind == .poundIf, let condition = node.condition {
            ifConfigStack.append(condition.trimmedDescription)
        } else {
            ifConfigStack.append("")
        }
        return .visitChildren
    }

    override func visitPost(_ node: IfConfigClauseSyntax) {
        _ = ifConfigStack.popLast()
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard hasMCPExtensionMarker(node) else { return .visitChildren }

        let extendedType = node.extendedType.trimmedDescription
        let condition = joinedIfConfigCondition()

        for member in node.memberBlock.members {
            collectIfMCPMember(
                member: member,
                extendedType: extendedType,
                condition: condition
            )
        }
        return .visitChildren
    }

    /// Returns `true` if the extension is decorated with `@MCPExtension`.
    private func hasMCPExtensionMarker(_ node: ExtensionDeclSyntax) -> Bool {
        for attr in node.attributes {
            guard let attrSyntax = attr.as(AttributeSyntax.self),
                  let identifier = attrSyntax.attributeName.as(IdentifierTypeSyntax.self),
                  identifier.name.text == "MCPExtension" else { continue }
            return true
        }
        return false
    }

    private func joinedIfConfigCondition() -> String {
        ifConfigStack
            .filter { !$0.isEmpty }
            .map { "(\($0))" }
            .joined(separator: " && ")
    }

    /// Inspects a single extension-member declaration and, if it carries an
    /// `@MCPTool`/`@MCPResource`/`@MCPPrompt` attribute, records the
    /// method in `byExtendedType`.
    private func collectIfMCPMember(
        member: MemberBlockItemSyntax,
        extendedType: String,
        condition: String
    ) {
        guard let funcDecl = member.decl.as(FunctionDeclSyntax.self) else { return }
        for attr in funcDecl.attributes {
            guard let attrSyntax = attr.as(AttributeSyntax.self),
                  let identifier = attrSyntax.attributeName.as(IdentifierTypeSyntax.self),
                  let kind = resolveContributionKind(
                    attributeName: identifier.name.text,
                    attribute: attrSyntax,
                    funcDecl: funcDecl
                  ) else { continue }
            var method = extractMethod(funcDecl: funcDecl, kind: kind)
            method.ifConfigCondition = condition
            byExtendedType[extendedType, default: []].append(method)
            break
        }
    }

    /// Resolves the contribution kind for a given attribute name. Returns
    /// `nil` if the attribute is not one of the MCP contribution macros.
    private func resolveContributionKind(
        attributeName: String,
        attribute: AttributeSyntax,
        funcDecl: FunctionDeclSyntax
    ) -> ContributionKind? {
        switch attributeName {
        case "MCPTool":
            return .tool(wireName: resolveToolWireName(attribute: attribute, funcDecl: funcDecl))
        case "MCPResource":
            return .resource(templates: resolveResourceTemplates(attribute: attribute))
        case "MCPPrompt":
            return .prompt
        default:
            return nil
        }
    }

    private func resolveToolWireName(attribute: AttributeSyntax, funcDecl: FunctionDeclSyntax) -> String {
        var wire = funcDecl.name.text
        guard let argList = attribute.arguments?.as(LabeledExprListSyntax.self) else { return wire }
        for arg in argList where arg.label?.text == "name" {
            if let literal = arg.expression.as(StringLiteralExprSyntax.self) {
                wire = literal.segments.description
            }
        }
        return wire
    }

    private func resolveResourceTemplates(attribute: AttributeSyntax) -> [String] {
        var templates: [String] = []
        guard let argList = attribute.arguments?.as(LabeledExprListSyntax.self) else { return templates }
        for arg in argList where arg.label == nil {
            if let literal = arg.expression.as(StringLiteralExprSyntax.self) {
                templates.append(literal.segments.description)
            } else if let array = arg.expression.as(ArrayExprSyntax.self) {
                for element in array.elements {
                    if let literal = element.expression.as(StringLiteralExprSyntax.self) {
                        templates.append(literal.segments.description)
                    }
                }
            }
        }
        return templates
    }
}

func extractMethod(funcDecl: FunctionDeclSyntax, kind: ContributionKind) -> DiscoveredMethod {
    let parameters = funcDecl.signature.parameterClause.parameters.map { param -> DiscoveredParameter in
        let name = param.secondName?.text ?? param.firstName.text
        let label = param.firstName.text
        let typeString = param.type.trimmedDescription
        let defaultValue = param.defaultValue?.value.trimmedDescription
        let isOptional = param.type.is(OptionalTypeSyntax.self)
            || param.type.is(ImplicitlyUnwrappedOptionalTypeSyntax.self)
            || typeString.hasSuffix("?")
            || typeString.hasSuffix("!")
        return DiscoveredParameter(
            name: name,
            label: label,
            typeString: typeString,
            defaultValue: defaultValue,
            isOptional: isOptional
        )
    }
    let returnType = funcDecl.signature.returnClause?.type.trimmedDescription
    let isAsync = funcDecl.signature.effectSpecifiers?.asyncSpecifier != nil
    let throwsClause = funcDecl.signature.effectSpecifiers?.throwsClause
    let throwsKeyword = throwsClause?.trimmedDescription
    let isThrowing = throwsClause != nil
    let parsedDoc = parseDocComment(trivia: funcDecl.leadingTrivia)
    return DiscoveredMethod(
        kind: kind,
        functionName: funcDecl.name.text,
        parameters: parameters,
        returnTypeString: returnType,
        isAsync: isAsync,
        isThrowing: isThrowing,
        throwsKeyword: throwsKeyword,
        docComment: parsedDoc.description,
        paramDocs: parsedDoc.params,
        returnsDoc: parsedDoc.returns,
        ifConfigCondition: ""
    )
}
