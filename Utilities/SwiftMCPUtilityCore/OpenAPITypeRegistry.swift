import Foundation
import SwiftMCP

final class OpenAPITypeRegistry {
    private var definitions: [String: String] = [:]
    var usedNames: Set<String> = []
    /// How generated struct properties are spelled. The wire key is kept in
    /// `CodingKeys`, so this only changes how the Swift side reads.
    private let propertyNaming: ProxyGenerator.ParameterNaming

    init(propertyNaming: ProxyGenerator.ParameterNaming = .verbatim) {
        self.propertyNaming = propertyNaming
    }
    /// Canonical form of the schema behind each titled type, so the same title
    /// with the same shape is one type wherever it appears.
    var fingerprints: [String: String] = [:]
    /// Whether each generated type can be `Hashable`. A struct is, when every
    /// property is — which is every schema-derived type, and none of SwiftMCP's
    /// own content types (`MCPText`, `MCPImage`, …), which are not `Hashable`.
    /// SwiftUI wants value equality on a model, so it is worth emitting
    /// wherever it can be.
    var hashable: [String: Bool] = [:]
    static let hashablePrimitives: Set<String> = [
        "String", "Double", "Bool", "Int", "Date", "URL", "Data", "UUID",
        "JSONValue", "JSONDictionary", "JSONArray"
    ]

    func swiftType(for schema: JSONSchema, suggestedName: String) -> String {
        switch schema {
        case .string(_, _, let format, _, _, _):
            return stringType(for: format)
        case .number:
            return "Double"
        case .boolean:
            return "Bool"
        case .array(let items, _, _, _):
            let itemType = swiftType(for: items, suggestedName: "\(suggestedName)Item")
            return "[\(itemType)]"
        case .oneOf(let schemas, _, _):
            if let knownType = knownSwiftMCPType(for: schemas) {
                return knownType
            }
            return "String"
        case .enum(let values, let title, let description, _, _):
            let (enumName, exists) = typeName(for: schema, title: title, suggestedName: suggestedName)
            if !exists {
                ensureEnum(name: enumName, values: values, description: description)
            }
            return enumName
        case .object(let object, _):
            return swiftTypeForObject(object, suggestedName: suggestedName)
        }
    }

    private func swiftTypeForObject(_ object: JSONSchema.Object, suggestedName: String) -> String {
        // If the object has only one key and it's an array, return the array type
        // directly — unless the server titled it, in which case it meant a type.
        if object.title == nil,
           object.properties.count == 1,
           let (_, arraySchema) = object.properties.first,
           case .array(let items, _, _, _) = arraySchema {
            let itemType = swiftType(for: items, suggestedName: "\(suggestedName)Item")
            return "[\(itemType)]"
        }
        if let knownType = knownSwiftMCPType(for: object) {
            return knownType
        }
        let (structName, exists) = typeName(for: .object(object), title: object.title, suggestedName: suggestedName)
        if !exists {
            ensureStruct(name: structName, object: object)
        }
        return structName
    }

    func renderDefinitions() -> [String] {
        let sorted = definitions.keys.sorted()
        return sorted.compactMap { definitions[$0] }
    }

    private func stringType(for format: String?) -> String {
        switch format ?? "" {
        case "date-time":
            return "Date"
        case "uri":
            return "URL"
        case "uuid":
            return "UUID"
        case "byte":
            return "Data"
        default:
            return "String"
        }
    }

    private func knownSwiftMCPType(for object: JSONSchema.Object) -> String? {
        if let toolContentType = knownToolContentType(for: object) {
            return toolContentType
        }
        if let resourceType = knownResourceType(for: object) {
            return resourceType
        }
        return nil
    }

    private func knownToolContentType(for object: JSONSchema.Object) -> String? {
        if matchesToolContent(object, type: "text", requiredKeys: ["type", "text"]) {
            return "MCPText"
        }

        if matchesToolContent(object, type: "image", requiredKeys: ["type", "data", "mimeType"]),
           matchesStringSchema(object.properties["data"], format: "byte"),
           matchesStringSchema(object.properties["mimeType"]) {
            return "MCPImage"
        }

        if matchesToolContent(object, type: "audio", requiredKeys: ["type", "data", "mimeType"]),
           matchesStringSchema(object.properties["data"], format: "byte"),
           matchesStringSchema(object.properties["mimeType"]) {
            return "MCPAudio"
        }

        if matchesToolContent(object, type: "resource_link", requiredKeys: ["type", "uri", "name"]) {
            return "MCPResourceLink"
        }

        if matchesToolContent(object, type: "resource", requiredKeys: ["type", "resource"]),
           case .object = object.properties["resource"] {
            return "MCPEmbeddedResource"
        }

        return nil
    }

    private func knownResourceType(for object: JSONSchema.Object) -> String? {
        let keys = Set(object.properties.keys)

        let resourceContentKeys: Set<String> = ["uri", "mimeType", "text", "blob"]
        if keys.isSubset(of: resourceContentKeys),
           keys.contains("uri"),
           object.required.contains("uri"),
           matchesStringSchema(object.properties["uri"]) {
            return "GenericResourceContent"
        }

        let resourceKeys: Set<String> = ["uri", "name", "description", "mimeType"]
        if keys == resourceKeys,
           object.required.contains("uri"),
           object.required.contains("name"),
           object.required.contains("description"),
           object.required.contains("mimeType"),
           matchesStringSchema(object.properties["uri"]),
           matchesStringSchema(object.properties["name"]),
           matchesStringSchema(object.properties["description"]),
           matchesStringSchema(object.properties["mimeType"]) {
            return "SimpleResource"
        }

        return nil
    }

    private func knownSwiftMCPType(for schemas: [JSONSchema]) -> String? {
        return nil
    }

    private func matchesToolContent(_ object: JSONSchema.Object, type: String, requiredKeys: Set<String>) -> Bool {
        guard requiredKeys.isSubset(of: Set(object.required)) else { return false }
        guard let typeValue = typeDiscriminator(object.properties["type"]),
              typeValue == type else { return false }
        return true
    }

    private func typeDiscriminator(_ schema: JSONSchema?) -> String? {
        guard let schema else { return nil }
        guard case .enum(let values, _, _, _, _) = schema, values.count == 1 else { return nil }
        return values[0]
    }

    private func matchesStringSchema(_ schema: JSONSchema?, format: String? = nil) -> Bool {
        guard let schema else { return false }
        guard case .string(_, _, let schemaFormat, _, _, _) = schema else { return false }
        if let format {
            return schemaFormat == format
        }
        return true
    }

    private func ensureStruct(name: String, object: JSONSchema.Object) {
        guard definitions[name] == nil else { return }

        // Properties first: resolving them defines any nested types, and says
        // whether this one can be Hashable.
        var propertyLines: [String] = []
        let (codingKeys, allHashable) = appendStructProperties(name: name, object: object, lines: &propertyLines)
        hashable[name] = allHashable

        var lines: [String] = []
        lines.append(contentsOf: docCommentLines(from: object.description, indent: ""))
        lines.append("public struct \(name): Codable, Sendable\(allHashable ? ", Hashable" : "") {")
        lines.append(contentsOf: propertyLines)

        if !codingKeys.isEmpty {
            lines.append("")
            lines.append("    private enum CodingKeys: String, CodingKey {")
            for key in codingKeys {
                lines.append(key.swift == key.original
                    ? "        case \(key.swift)"
                    : "        case \(key.swift) = \"\(key.original)\"")
            }
            lines.append("    }")
        }

        lines.append("}")
        definitions[name] = lines.joined(separator: "\n")
    }

    private func appendStructProperties(
        name: String,
        object: JSONSchema.Object,
        lines: inout [String]
    ) -> (codingKeys: [(swift: String, original: String)], allHashable: Bool) {
        let sortedProperties = object.properties.keys.sorted()
        var codingKeys: [(swift: String, original: String)] = []
        var allHashable = true

        for key in sortedProperties {
            guard let schema = object.properties[key] else { continue }
            let swiftName = ProxyGenerator.parameterIdentifier(from: key, naming: propertyNaming)
            let typeName = swiftType(for: schema, suggestedName: "\(name)\(ProxyGenerator.pascalCase(key))")
            let isRequired = object.required.contains(key)
            let propertyType = isRequired ? typeName : "\(typeName)?"
            allHashable = allHashable && isHashable(typeName)
            lines.append(contentsOf: docCommentLines(from: schemaDescription(schema), indent: "    "))
            lines.append("    public let \(swiftName): \(propertyType)")
            codingKeys.append((swift: swiftName, original: key))
        }

        // A CodingKeys enum is only needed when a key was respelled — but once
        // it exists, synthesised Codable requires every property in it.
        let anyRenamed = codingKeys.contains { $0.swift != $0.original }
        return (anyRenamed ? codingKeys : [], allHashable)
    }

    private func ensureEnum(name: String, values: [String], description: String?) {
        guard definitions[name] == nil else { return }
        hashable[name] = true
        var lines: [String] = []
        lines.append(contentsOf: docCommentLines(from: description, indent: ""))
        lines.append("public enum \(name): String, Codable, Sendable, CaseIterable {")

        var usedCases: Set<String> = []
        for (index, value) in values.enumerated() {
            var caseName = ProxyGenerator.swiftIdentifier(from: value, lowerCamel: true)
            if usedCases.contains(caseName) {
                caseName = "\(caseName)_\(index)"
            }
            usedCases.insert(caseName)
            lines.append("    case \(caseName) = \"\(value)\"")
        }
        lines.append("}")
        definitions[name] = lines.joined(separator: "\n")
    }

    private func docCommentLines(from text: String?, indent: String) -> [String] {
        guard let text, !text.isEmpty else { return [] }
        let parts = text.split(separator: "\n").map(String.init)
        return parts.map { "\(indent)/// \($0)" }
    }

    private func schemaDescription(_ schema: JSONSchema) -> String? {
        switch schema {
        case .string(_, let description, _, _, _, _):
            return description
        case .number(_, let description, _, _, _):
            return description
        case .boolean(_, let description, _):
            return description
        case .array(_, _, let description, _):
            return description
        case .object(let object, _):
            return object.description
        case .enum(_, _, let description, _, _):
            return description
        case .oneOf(_, _, let description):
            return description
        }
    }
}
