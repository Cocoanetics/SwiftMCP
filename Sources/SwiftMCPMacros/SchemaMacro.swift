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
        // Handle struct declarations
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            let diagnostic = Diagnostic(node: node, message: SchemaDiagnostic.onlyStructs)
            context.diagnose(diagnostic)
            return []
        }

        // Extract struct name
        let structName = structDecl.name.text

        // Extract property descriptions from documentation
        let documentation = Documentation(from: structDecl.leadingTrivia.description)

        // Extract property information
        var propertyString = ""
        var propertyInfos: [(name: String, type: String, defaultValue: String?)] = []

        // Process all members, but only properties (ignore nested structs)
        for member in structDecl.memberBlock.members {
            if let property = member.decl.as(VariableDeclSyntax.self) {
                // Process regular property
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
            }
            // Ignore nested structs - they should have their own @Schema annotation
        }

        // Create a registration statement
        let registrationDecl = """
        /// generated
        public static let schemaMetadata = SchemaMetadata(name: "\(structName)", description: \(documentation.description.isEmpty ? "nil" : "\"\(documentation.description.escapedForSwiftString)\""), parameters: [\(propertyString)])
        """

        return [DeclSyntax(stringLiteral: registrationDecl)]
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

    private static func processProperty(
        property: VariableDeclSyntax,
        documentation: Documentation,
        context: MacroExpansionContext
    ) throws -> (String, (name: String, type: String, defaultValue: String?)) {
        // Get the property name and type
        let propertyName = property.bindings.first?.pattern.as(IdentifierPatternSyntax.self)?.identifier.text ?? ""
        let propertyType = property.bindings.first?.typeAnnotation?.type.description.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""

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
        let propertyStr = "SchemaPropertyInfo(name: \"\(schemaName)\", type: \(baseType).self, description: \(propertyDescription), defaultValue: \(defaultValue) as Sendable?, isRequired: \(isRequired))"

        return (propertyStr, (name: propertyName, type: propertyType, defaultValue: defaultValue))
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

                        for element in enumCase.elements {
                            if element.name.text == propertyName {
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
            }
            currentParent = current.parent
        }

        return nil
    }
}

// Diagnostic messages for the Schema macro
enum SchemaDiagnostic: DiagnosticMessage {
    case onlyStructs

    var message: String {
        switch self {
            case .onlyStructs:
                return "@Schema can only be applied to struct declarations"
        }
    }

    var diagnosticID: MessageID {
        switch self {
            case .onlyStructs:
                return MessageID(domain: "SchemaMacro", id: "onlyStructs")
        }
    }

    var severity: DiagnosticSeverity {
        switch self {
            case .onlyStructs:
                return .error
        }
    }
} 
