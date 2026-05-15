import Foundation
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/**
 Implementation of the Schema macro.
 
 This macro transforms a struct into a schema by generating metadata about its properties.
 
 Example usage:
 ```swift
 /// A person's contact information
 @Schema
 struct ContactInfo {
     /// The person's full name
     let name: String
     
     /// The person's email address
     let email: String
     
     /// The person's phone number (optional)
     let phone: String?
     
     /// The person's age
     let age: Int = 0
     
     /// The person's address
     let address: Address
 }
 
 /// A person's address
 @Schema
 struct Address {
     /// The street name
     let street: String
     
     /// The city name
     let city: String
 }
 ```
 
 - Note: The macro extracts documentation from the struct's comments for:
   * Struct description
   * Property descriptions
 
 - Attention: The macro will emit diagnostics for:
   * Non-struct declarations
 */
public struct SchemaMacro: MemberMacro, ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        try expansion(of: node, providingMembersOf: declaration, in: context)
    }

    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            let diagnostic = Diagnostic(node: node, message: SchemaDiagnostic.onlyStructs)
            context.diagnose(diagnostic)
            return []
        }

        let structName = structDecl.name.text
        let documentation = Documentation(from: structDecl.leadingTrivia.description)
        let (propertyString, propertyInfos) = try collectProperties(
            of: structDecl,
            documentation: documentation,
            context: context
        )

        let registrationDecl = makeRegistrationDeclaration(
            structName: structName,
            documentation: documentation,
            propertyString: propertyString
        )

        var declarations = [DeclSyntax(stringLiteral: registrationDecl)]
        declarations.append(DeclSyntax(stringLiteral: makeClientReturnTypealias(
            structName: structName,
            propertyInfos: propertyInfos
        )))
        return declarations
    }

    /// Walks the struct members collecting property metadata. Emits a
    /// diagnostic for nested structs lacking `@Schema`.
    private static func collectProperties(
        of structDecl: StructDeclSyntax,
        documentation: Documentation,
        context: MacroExpansionContext
    ) throws -> (String, [PropertyInfo]) {
        var propertyString = ""
        var propertyInfos: [PropertyInfo] = []

        for member in structDecl.memberBlock.members {
            if let property = member.decl.as(VariableDeclSyntax.self) {
                guard shouldIncludeProperty(property) else { continue }
                let (propertyStr, propertyInfo) = try processProperty(
                    property: property,
                    documentation: documentation,
                    context: context
                )
                if !propertyString.isEmpty {
                    propertyString += ", "
                }
                propertyString += propertyStr
                propertyInfos.append(propertyInfo)
            } else if let nestedStruct = member.decl.as(StructDeclSyntax.self) {
                diagnoseNestedStructIfNeeded(nestedStruct, context: context)
            }
        }

        return (propertyString, propertyInfos)
    }

    private static func diagnoseNestedStructIfNeeded(
        _ nestedStruct: StructDeclSyntax,
        context: MacroExpansionContext
    ) {
        let hasSchemaAttribute = nestedStruct.attributes.contains { attribute in
            guard let identifierAttr = attribute.as(AttributeSyntax.self),
                  let identifier = identifierAttr.attributeName.as(IdentifierTypeSyntax.self) else {
                return false
            }
            return identifier.name.text == "Schema"
        }
        guard !hasSchemaAttribute else { return }
        let diagnostic = Diagnostic(
            node: nestedStruct.structKeyword,
            message: SchemaDiagnostic.nestedStructNeedsSchema(nestedStruct.name.text)
        )
        context.diagnose(diagnostic)
    }

    private static func makeRegistrationDeclaration(
        structName: String,
        documentation: Documentation,
        propertyString: String
    ) -> String {
        let descriptionArg = documentation.description.isEmpty
            ? "nil"
            : "\"\(documentation.description.escapedForSwiftString)\""
        return """
        /// generated
        public static let schemaMetadata = SchemaMetadata(
            name: "\(structName)",
            description: \(descriptionArg),
            parameters: [\(propertyString)]
        )
        """
    }

    /// Generates the `MCPClientReturn` typealias for the proxy generator.
    /// Single-array wrapper structs (exactly one stored array property) resolve
    /// to `[Element]`; all other structs resolve to `Self`.
    private static func makeClientReturnTypealias(
        structName: String,
        propertyInfos: [PropertyInfo]
    ) -> String {
        if propertyInfos.count == 1,
           let onlyProp = propertyInfos.first,
           let elementType = Self.arrayElementType(
               from: onlyProp.type.trimmingCharacters(in: .whitespacesAndNewlines)
           ) {
            return "public typealias MCPClientReturn = [\(elementType)]"
        }
        return "public typealias MCPClientReturn = \(structName)"
    }

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        // Check if the declaration already conforms to SchemaRepresentable
        let inheritedTypes = declaration.inheritanceClause?.inheritedTypes ?? []
        let alreadyConformsToSchemaRepresentable = inheritedTypes.contains { type in
            type.type.trimmedDescription == "SchemaRepresentable"
        }

        // If it already conforms, don't add the conformance again
        if alreadyConformsToSchemaRepresentable {
            return []
        }

        // Create an extension that adds the SchemaRepresentable protocol conformance
        let extensionDecl = try ExtensionDeclSyntax("extension \(type): SchemaRepresentable {}")

        return [extensionDecl]
    }

    struct PropertyInfo {
        let name: String
        let type: String
        let defaultValue: String?
    }

    private static func processProperty(
        property: VariableDeclSyntax,
        documentation: Documentation,
        context: MacroExpansionContext
    ) throws -> (String, PropertyInfo) {
        // Get the property name and type
        let propertyName = property.bindings.first?
            .pattern.as(IdentifierPatternSyntax.self)?.identifier.text ?? ""
        let propertyType = property.bindings.first?
            .typeAnnotation?.type.description
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""

        // Get property description from property's documentation
        var propertyDescription = "nil"
        let propertyDoc = Documentation(from: property.leadingTrivia.description)
        if !propertyDoc.description.isEmpty {
            propertyDescription = "\"\(propertyDoc.description.escapedForSwiftString)\""
        }

        // Check for default value
        var defaultValue = "nil"
        if let initializer = property.bindings.first?.initializer {
            let rawValue = initializer.value.description.trimmingCharacters(in: CharacterSet.whitespaces)

            // Handle different types of default values
            if rawValue.hasPrefix(".") {
                defaultValue = "\(propertyType)\(rawValue)"
            } else if rawValue.contains(".") ||
                rawValue == "true" || rawValue == "false" ||
                Double(rawValue) != nil ||
                rawValue == "nil" ||
                (rawValue.hasPrefix("[") && rawValue.hasSuffix("]")) {
                defaultValue = rawValue
            } else if let stringLiteral = initializer.value.as(StringLiteralExprSyntax.self) {
                defaultValue = "\"\(stringLiteral.segments.description)\""
            } else {
                defaultValue = "\"\(rawValue)\""
            }
        }

        // Create property info with isRequired property
        let isOptionalType = propertyType.hasSuffix("?") || propertyType.hasSuffix("!")
        let isRequired = defaultValue == "nil" && !isOptionalType

        // Strip optional marker from type for JSON schema
        let baseType = isOptionalType ? String(propertyType.dropLast()) : propertyType

        // Get the coding key raw value if available, otherwise use property name
        let schemaName = getCodingKeyRawValue(for: propertyName, in: Syntax(property)) ?? propertyName

        // Create parameter info with the type directly
        let propertyStr = "SchemaPropertyInfo(name: \"\(schemaName)\", type: \(baseType).self, "
            + "description: \(propertyDescription), "
            + "defaultValue: \(defaultValue) as Sendable?, "
            + "isRequired: \(isRequired))"

        return (
            propertyStr,
            PropertyInfo(name: propertyName, type: propertyType, defaultValue: defaultValue)
        )
    }

    private static func shouldIncludeProperty(_ property: VariableDeclSyntax) -> Bool {
        let modifiers = property.modifiers
        if modifiers.contains(where: { $0.name.text == "static" || $0.name.text == "class" }) {
            return false
        }

        for binding in property.bindings where binding.accessorBlock != nil {
            return false
        }

        return true
    }

    /// Extracts the element type from an array type string, or returns nil if not an array.
    /// Handles `[Foo]` and `Array<Foo>` syntax. Returns nil for optional arrays like `[Foo]?`.
    private static func arrayElementType(from typeString: String) -> String? {
        // Exclude optional types
        if typeString.hasSuffix("?") || typeString.hasSuffix("!") {
            return nil
        }

        if typeString.hasPrefix("[") && typeString.hasSuffix("]") {
            let inner = typeString.dropFirst().dropLast()
            let trimmed = inner.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        if typeString.hasPrefix("Array<") && typeString.hasSuffix(">") {
            let start = typeString.index(typeString.startIndex, offsetBy: 6)
            let end = typeString.index(before: typeString.endIndex)
            let trimmed = typeString[start..<end].trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        return nil
    }

    /// Gets the raw value from CodingKeys enum for a given property name
    private static func getCodingKeyRawValue(for propertyName: String, in parent: Syntax?) -> String? {
        // Traverse up until we find the struct declaration
        var currentParent = parent
        while let current = currentParent {
            if let structDecl = current.as(StructDeclSyntax.self) {
                // Look for CodingKeys enum in the struct members
                for member in structDecl.memberBlock.members {
                    guard let enumDecl = member.decl.as(EnumDeclSyntax.self),
                          enumDecl.name.text == "CodingKeys",
                          enumDecl.modifiers.contains(where: { $0.name.text == "private" }) else {
                        continue
                    }

                    // Get all inherited types as strings
                    let inheritedTypeDescriptions = enumDecl.inheritanceClause?.inheritedTypes.map {
                        $0.type.description.trimmingCharacters(in: .whitespacesAndNewlines)
                    } ?? []

                    guard inheritedTypeDescriptions.contains("String"),
                          inheritedTypeDescriptions.contains("CodingKey") else {
                        continue
                    }

                    // Found CodingKeys enum, look for the case matching our property
                    for member in enumDecl.memberBlock.members {
                        guard let enumCase = member.decl.as(EnumCaseDeclSyntax.self) else { continue }

                        for element in enumCase.elements where element.name.text == propertyName {
                            // Found matching case, check for raw value
                            if let rawValue = element.rawValue?.value {
                                // Handle string literal
                                if let stringLiteral = rawValue.as(StringLiteralExprSyntax.self) {
                                    return stringLiteral.segments.description
                                        .trimmingCharacters(in: .init(charactersIn: "\""))
                                }
                            }
                            // If no raw value, use the case name
                            return element.name.text
                        }
                    }
                }
            }
            currentParent = current.parent
        }

        return nil
    }
}

// Diagnostic messages for the Schema macro
enum SchemaDiagnostic: DiagnosticMessage {
    case onlyStructs
    case nestedStructNeedsSchema(String)

    var message: String {
        switch self {
        case .onlyStructs:
            return "@Schema can only be applied to struct declarations"
        case .nestedStructNeedsSchema(let structName):
            return "Nested struct '\(structName)' needs the @Schema annotation"
        }
    }

    var diagnosticID: MessageID {
        switch self {
        case .onlyStructs:
            return MessageID(domain: "SchemaMacro", id: "onlyStructs")
        case .nestedStructNeedsSchema:
            return MessageID(domain: "SchemaMacro", id: "nestedStructNeedsSchema")
        }
    }

    var severity: DiagnosticSeverity {
        switch self {
        case .onlyStructs:
            return .error
        case .nestedStructNeedsSchema:
            return .warning
        }
    }
}
