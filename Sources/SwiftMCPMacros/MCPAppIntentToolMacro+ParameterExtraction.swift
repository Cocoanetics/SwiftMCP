//
//  MCPAppIntentToolMacro+ParameterExtraction.swift
//  SwiftMCPMacros
//
//  Helpers for `@MCPAppIntentTool` that walk an AppIntent declaration to
//  discover its `@Parameter` properties, infer parameter metadata, and
//  inspect the `perform()` return type.
//

import Foundation
import SwiftSyntax
import SwiftSyntaxMacros

extension MCPAppIntentToolMacro {
    static func typeName(from declaration: some DeclGroupSyntax) -> String? {
        if let structDecl = declaration.as(StructDeclSyntax.self) {
            return structDecl.name.text
        }
        if let classDecl = declaration.as(ClassDeclSyntax.self) {
            return classDecl.name.text
        }
        if let actorDecl = declaration.as(ActorDeclSyntax.self) {
            return actorDecl.name.text
        }
        return nil
    }

    static func isAppIntentDeclaration(_ declaration: some DeclGroupSyntax) -> Bool {
        let inheritedTypes = declaration.inheritanceClause?.inheritedTypes ?? []
        return inheritedTypes.contains { type in
            let name = type.type.trimmedDescription
            return name == "AppIntent" || name.hasSuffix(".AppIntent")
        }
    }

    /// Discovers `@Parameter` properties and constructs `AppIntentParameter`
    /// records for them.
    static func appIntentParameters(from declaration: some DeclGroupSyntax) -> [AppIntentParameter] {
        var parameters: [AppIntentParameter] = []

        for member in declaration.memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }
            guard let parameterAttribute = parameterAttribute(on: varDecl) else { continue }
            parameters.append(contentsOf: parametersForBindings(
                of: varDecl,
                attribute: parameterAttribute
            ))
        }

        return parameters
    }

    /// Returns the `@Parameter` attribute if present on a variable declaration.
    private static func parameterAttribute(on varDecl: VariableDeclSyntax) -> AttributeSyntax? {
        return varDecl.attributes.compactMap { $0.as(AttributeSyntax.self) }.first(where: { attr in
            guard let identifier = attr.attributeName.as(IdentifierTypeSyntax.self) else { return false }
            return identifier.name.text == "Parameter"
        })
    }

    private static func parametersForBindings(
        of varDecl: VariableDeclSyntax,
        attribute: AttributeSyntax
    ) -> [AppIntentParameter] {
        var parameters: [AppIntentParameter] = []
        for binding in varDecl.bindings {
            guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else { continue }
            guard let typeSyntax = binding.typeAnnotation?.type else { continue }
            parameters.append(makeParameter(
                varDecl: varDecl,
                attribute: attribute,
                name: pattern.identifier.text,
                typeSyntax: typeSyntax,
                initializer: binding.initializer
            ))
        }
        return parameters
    }

    /// Builds an `AppIntentParameter` from the binding components.
    private static func makeParameter(
        varDecl: VariableDeclSyntax,
        attribute: AttributeSyntax,
        name: String,
        typeSyntax: TypeSyntax,
        initializer: InitializerClauseSyntax?
    ) -> AppIntentParameter {
        let typeString = typeSyntax.description.trimmingCharacters(in: .whitespacesAndNewlines)
        let isOptionalType = isOptionalType(typeSyntax, typeString: typeString)
        let baseTypeString = baseTypeString(
            from: typeSyntax,
            typeString: typeString,
            isOptional: isOptionalType
        )

        let description = parameterDescription(varDecl: varDecl, attribute: attribute)
        let defaultValueForMetadata = processDefaultValue(
            initializer?.value,
            paramTypeString: baseTypeString,
            isArray: typeSyntax.is(ArrayTypeSyntax.self) || typeString.hasPrefix("[")
        )

        return AppIntentParameter(
            name: name,
            typeString: typeString,
            baseTypeString: baseTypeString,
            defaultValueForMetadata: defaultValueForMetadata,
            description: description,
            isOptionalType: isOptionalType
        )
    }

    private static func isOptionalType(_ typeSyntax: TypeSyntax, typeString: String) -> Bool {
        return typeSyntax.is(OptionalTypeSyntax.self)
            || typeSyntax.is(ImplicitlyUnwrappedOptionalTypeSyntax.self)
            || typeString.hasSuffix("?")
            || typeString.hasSuffix("!")
    }

    private static func baseTypeString(
        from typeSyntax: TypeSyntax,
        typeString: String,
        isOptional: Bool
    ) -> String {
        guard isOptional else { return typeString }
        if typeString.hasSuffix("?") || typeString.hasSuffix("!") {
            return String(typeString.dropLast())
        }
        if let optType = typeSyntax.as(OptionalTypeSyntax.self) {
            return optType.wrappedType.description.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let iuoType = typeSyntax.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
            return iuoType.wrappedType.description.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return typeString
    }

    /// Resolves the documentation/title-derived description for a parameter
    /// binding. Returns the raw description literal (with surrounding quotes)
    /// or nil when no description is available.
    private static func parameterDescription(
        varDecl: VariableDeclSyntax,
        attribute: AttributeSyntax
    ) -> String? {
        let propertyDoc = Documentation(from: varDecl.leadingTrivia.description)
        if !propertyDoc.description.isEmpty {
            return "\"\(propertyDoc.description.escapedForSwiftString)\""
        }
        if let title = parameterTitle(from: attribute) {
            return "\"\(title.escapedForSwiftString)\""
        }
        return nil
    }

    static func appIntentReturnValueType(from declaration: some DeclGroupSyntax) -> String? {
        let functionDecls = declaration.memberBlock.members.compactMap { $0.decl.as(FunctionDeclSyntax.self) }
        guard let performDecl = functionDecls.first(where: { $0.name.text == "perform" }) else { return nil }
        guard let returnType = performDecl.signature.returnClause?.type else { return nil }
        return returnsValueTypeName(from: returnType)
    }

    private static func returnsValueTypeName(from returnType: TypeSyntax) -> String? {
        let raw = returnType.description
        return extractGenericArgument(named: "ReturnsValue", from: raw)
    }

    /// Extracts the inner generic argument from `<name><...>` in a type
    /// string, handling nested angle brackets.
    private static func extractGenericArgument(named name: String, from raw: String) -> String? {
        guard let nameRange = raw.range(of: name) else { return nil }
        var index = nameRange.upperBound

        while index < raw.endIndex, raw[index].isWhitespace {
            index = raw.index(after: index)
        }

        if index == raw.endIndex {
            return nil
        }

        if raw[index] != "<" {
            guard let next = raw[index...].firstIndex(of: "<") else { return nil }
            index = next
        }

        guard raw[index] == "<" else { return nil }

        let start = raw.index(after: index)
        var depth = 1
        var current = start

        while current < raw.endIndex {
            let char = raw[current]
            if char == "<" {
                depth += 1
            } else if char == ">" {
                depth -= 1
                if depth == 0 {
                    return raw[start..<current].trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            current = raw.index(after: current)
        }

        return nil
    }

    private static func parameterTitle(from attribute: AttributeSyntax) -> String? {
        guard let arguments = attribute.arguments?.as(LabeledExprListSyntax.self) else { return nil }
        for argument in arguments {
            if argument.label?.text == "title" || argument.label == nil {
                if let stringLiteral = argument.expression.as(StringLiteralExprSyntax.self) {
                    return stringLiteral.segments.description
                }
            }
        }
        return nil
    }

    static func processDefaultValue(
        _ defaultExpr: ExprSyntax?,
        paramTypeString: String,
        isArray: Bool
    ) -> String {
        guard let expr = defaultExpr else { return "nil" }

        let rawValue = expr.description.trimmingCharacters(in: .whitespaces)

        if expr.is(NilLiteralExprSyntax.self) {
            return "nil"
        } else if let stringLiteral = expr.as(StringLiteralExprSyntax.self) {
            return "\"\(stringLiteral.segments.description.escapedForSwiftString)\""
        } else if expr.is(BooleanLiteralExprSyntax.self) ||
                    expr.is(IntegerLiteralExprSyntax.self) ||
                    expr.is(FloatLiteralExprSyntax.self) {
            return rawValue
        } else if rawValue.hasPrefix(".") {
            return "\(paramTypeString)\(rawValue)"
        } else if expr.is(ArrayExprSyntax.self) && rawValue == "[]" {
            if isArray {
                return "[] as \(paramTypeString)"
            }
            return "[]"
        }

        return rawValue
    }
}
