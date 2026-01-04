import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import AnyCodable
import SwiftMCP
import SwiftSyntax
import SwiftSyntaxBuilder

public enum ProxyGenerator {
    public struct HeaderMetadata: Sendable {
        public let fileName: String
        public let serverName: String?
        public let serverVersion: String?
        public let serverDescription: String?
        public let source: String?
        public let openAPI: String?

        public init(
            fileName: String,
            serverName: String?,
            serverVersion: String?,
            serverDescription: String?,
            source: String?,
            openAPI: String?
        ) {
            self.fileName = fileName
            self.serverName = serverName
            self.serverVersion = serverVersion
            self.serverDescription = serverDescription
            self.source = source
            self.openAPI = openAPI
        }
    }

    public static func generate(
        typeName: String,
        tools: [MCPTool],
        openapiReturnSchemas: [String: OpenAPIReturnInfo] = [:],
        fileName: String? = nil,
        headerMetadata: HeaderMetadata? = nil
    ) -> SourceFileSyntax {
        let registry = OpenAPITypeRegistry()
        let returnTypes = buildReturnTypes(
            tools: tools,
            openapiReturnSchemas: openapiReturnSchemas,
            registry: registry
        )
        let typeDefinitions = registry.renderDefinitions()
        let resolvedFileName = fileName ?? "\(typeName).swift"
        let metadata = headerMetadata ?? HeaderMetadata(
            fileName: resolvedFileName,
            serverName: nil,
            serverVersion: nil,
            serverDescription: nil,
            source: nil,
            openAPI: nil
        )
        let headerComment = makeHeaderComment(metadata: metadata)
        let typeDocComment = makeTypeDocCommentLines(metadata: metadata)
        let actorSource = makeActorSource(
            typeName: typeName,
            tools: tools,
            returnTypes: returnTypes,
            typeDefinitions: typeDefinitions,
            typeDocComment: typeDocComment
        )

        let headerAndImports = "\(headerComment)\n\nimport Foundation\nimport SwiftMCP\n"

        return SourceFileSyntax {
            DeclSyntax(stringLiteral: headerAndImports)
            DeclSyntax(stringLiteral: "\n\(actorSource)")
        }
    }

    public static func defaultTypeName(serverName: String?) -> String {
        let base = serverName.flatMap { pascalCase($0) } ?? "MCPServer"
        return "\(base)Proxy"
    }

    private static func makeActorSource(
        typeName: String,
        tools: [MCPTool],
        returnTypes: [String: OpenAPIReturnInfo],
        typeDefinitions: [String],
        typeDocComment: [String]
    ) -> String {
        var lines: [String] = []
        if !typeDocComment.isEmpty {
            lines.append(contentsOf: typeDocComment)
        }
        lines.append("public actor \(typeName) {")
        if !typeDefinitions.isEmpty {
            lines.append("    // MARK: - Declarations")
            lines.append(contentsOf: indentDefinitions(typeDefinitions, indent: "    "))
            lines.append("")
        }
        lines.append("    // MARK: - Public Properties")
        lines.append("    public let proxy: MCPServerProxy")
        lines.append("")
        lines.append("    // MARK: - Initialization")
        lines.append("    public init(proxy: MCPServerProxy) {")
        lines.append("        self.proxy = proxy")
        lines.append("    }")

        let sortedTools = tools.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if !sortedTools.isEmpty {
            lines.append("")
            lines.append("    // MARK: - Functions")
        }
        for tool in sortedTools {
            lines.append("")
            let returnInfo = returnTypes[tool.name]
            lines.append(contentsOf: makeMethodLines(tool: tool, returnInfo: returnInfo))
        }

        lines.append("}")
        return lines.joined(separator: "\n")
    }

    private static func makeHeaderComment(metadata: HeaderMetadata) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone.current
        formatter.formatOptions = [.withInternetDateTime, .withTimeZone]
        let timestamp = formatter.string(from: Date())

        var lines: [String] = [
            "//",
            "//  \(metadata.fileName)",
            "//  Generated: \(timestamp)",
            "//  Server: \(serverDisplayName(from: metadata))"
        ]

        if let source = metadata.source, !source.isEmpty {
            lines.append("//  Source: \(source)")
        }
        if let openAPI = metadata.openAPI, !openAPI.isEmpty {
            lines.append("//  OpenAPI: \(openAPI)")
        }

        lines.append("//")
        return lines.joined(separator: "\n")
    }

    private static func makeTypeDocCommentLines(metadata: HeaderMetadata) -> [String] {
        let name = metadata.serverName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let version = metadata.serverVersion?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let summary: String
        if !name.isEmpty {
            if !version.isEmpty {
                summary = "A generated proxy for the \(name) MCP server (\(version))."
            } else {
                summary = "A generated proxy for the \(name) MCP server."
            }
        } else {
            summary = "A generated MCP server proxy."
        }

        var commentBody = summary
        if let description = metadata.serverDescription?.trimmingCharacters(in: .whitespacesAndNewlines),
           !description.isEmpty {
            commentBody = description
        }
        if let openAPI = metadata.openAPI, !openAPI.isEmpty {
            commentBody += "\n\nReturn types are enhanced using OpenAPI metadata."
        }

        return docBlockLines(commentBody)
    }

    private static func docBlockLines(_ text: String) -> [String] {
        var lines: [String] = ["/**"]
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            lines.append(" \(line)")
        }
        lines.append("*/")
        return lines
    }

    private static func serverDisplayName(from metadata: HeaderMetadata) -> String {
        let name = metadata.serverName ?? "unknown"
        let version = metadata.serverVersion ?? "unknown"
        return "\(name) (\(version))"
    }

    private static func indentDefinitions(_ definitions: [String], indent: String) -> [String] {
        var lines: [String] = []
        for (index, definition) in definitions.enumerated() {
            let indented = definition
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { line -> String in
                    if line.isEmpty {
                        return ""
                    }
                    return indent + line
                }
            lines.append(contentsOf: indented)
            if index < definitions.count - 1 {
                lines.append("")
            }
        }
        return lines
    }

    private static func makeMethodLines(tool: MCPTool, returnInfo: OpenAPIReturnInfo?) -> [String] {
        var lines: [String] = []
        let methodName = swiftIdentifier(from: tool.name, lowerCamel: true)

        let parameters = methodParameters(for: tool)
        lines.append(contentsOf: docCommentLines(tool: tool, parameters: parameters, returnInfo: returnInfo))

        let signature = parameters.map { $0.signature }.joined(separator: ", ")
        let returnType = returnInfo?.typeName ?? "String"
        lines.append("    public func \(methodName)(\(signature)) async throws -> \(returnType) {")

        if parameters.isEmpty {
            lines.append("        let text = try await proxy.callTool(\"\(tool.name)\")")
            lines.append(contentsOf: returnLines(returnType: returnType))
            lines.append("    }")
            return lines
        }

        lines.append("        var arguments: [String: any Sendable] = [:]")
        for param in parameters {
            let key = param.originalName
            if param.isOptional {
                if param.needsEncoding {
                    lines.append("        if let \(param.swiftName) { arguments[\"\(key)\"] = MCPToolArgumentEncoder.encode(\(param.swiftName)) }")
                } else {
                    lines.append("        if let \(param.swiftName) { arguments[\"\(key)\"] = \(param.swiftName) }")
                }
            } else {
                if param.needsEncoding {
                    lines.append("        arguments[\"\(key)\"] = MCPToolArgumentEncoder.encode(\(param.swiftName))")
                } else {
                    lines.append("        arguments[\"\(key)\"] = \(param.swiftName)")
                }
            }
        }
        lines.append("        let text = try await proxy.callTool(\"\(tool.name)\", arguments: arguments)")
        lines.append(contentsOf: returnLines(returnType: returnType))
        lines.append("    }")
        return lines
    }

    private static func docCommentLines(
        tool: MCPTool,
        parameters: [MethodParameter],
        returnInfo: OpenAPIReturnInfo?
    ) -> [String] {
        var lines: [String] = []
        var bodyLines: [String] = []

        if let description = tool.description, !description.isEmpty {
            for line in description.split(separator: "\n") {
                bodyLines.append(String(line))
            }
        }

        for param in parameters {
            if let docLine = param.docLine, !docLine.isEmpty {
                bodyLines.append("- Parameter \(param.swiftName): \(docLine)")
            }
        }

        if let returnDescription = returnInfo?.description, !returnDescription.isEmpty {
            bodyLines.append("- Returns: \(returnDescription)")
        }

        if bodyLines.isEmpty {
            return lines
        }

        lines.append("    /**")
        for bodyLine in bodyLines {
            lines.append("     \(bodyLine)")
        }
        lines.append("     */")
        return lines
    }

    private struct MethodParameter {
        let originalName: String
        let swiftName: String
        let signature: String
        let isOptional: Bool
        let needsEncoding: Bool
        let docLine: String?
    }

    private static func methodParameters(for tool: MCPTool) -> [MethodParameter] {
        guard case .object(let object, _) = tool.inputSchema else {
            return []
        }

        let required = Set(object.required)
        let sortedKeys = object.properties.keys.sorted()
        return sortedKeys.compactMap { key in
            guard let schema = object.properties[key] else {
                return nil
            }
            let swiftName = swiftIdentifier(from: key, lowerCamel: true)
            let typeInfo = swiftTypeInfo(for: schema)
            let defaultLiteral = defaultValueLiteral(for: schema, typeInfo: typeInfo)
            let isDefaultNil = defaultLiteral == "nil"
            let hasDefault = defaultLiteral != nil
            let isOptional = isDefaultNil || (!required.contains(key) && !hasDefault)
            let typeName = isOptional ? "\(typeInfo.typeName)?" : typeInfo.typeName
            let defaultValue: String
            if let defaultLiteral {
                defaultValue = " = \(defaultLiteral)"
            } else if isOptional {
                defaultValue = " = nil"
            } else {
                defaultValue = ""
            }
            let signature = "\(swiftName): \(typeName)\(defaultValue)"
            let docLine = parameterDocLine(schema: schema)
            return MethodParameter(
                originalName: key,
                swiftName: swiftName,
                signature: signature,
                isOptional: isOptional,
                needsEncoding: typeInfo.needsEncoding,
                docLine: docLine
            )
        }
    }

    private struct SwiftTypeInfo {
        let typeName: String
        let needsEncoding: Bool
    }

    private static func swiftTypeInfo(for schema: JSONSchema) -> SwiftTypeInfo {
        switch schema {
            case .string(_, _, let format, _, _, _):
                switch format ?? "" {
                    case "date-time":
                        return SwiftTypeInfo(typeName: "Date", needsEncoding: true)
                    case "uri":
                        return SwiftTypeInfo(typeName: "URL", needsEncoding: true)
                    case "uuid":
                        return SwiftTypeInfo(typeName: "UUID", needsEncoding: true)
                    case "byte":
                        return SwiftTypeInfo(typeName: "Data", needsEncoding: true)
                    default:
                        return SwiftTypeInfo(typeName: "String", needsEncoding: false)
                }
            case .number:
                return SwiftTypeInfo(typeName: "Double", needsEncoding: false)
            case .boolean:
                return SwiftTypeInfo(typeName: "Bool", needsEncoding: false)
            case .array(let items, _, _, _):
                let elementInfo = swiftTypeInfo(for: items)
                return SwiftTypeInfo(typeName: "[\(elementInfo.typeName)]", needsEncoding: elementInfo.needsEncoding)
            case .object:
                return SwiftTypeInfo(typeName: "[String: any Sendable]", needsEncoding: false)
            case .enum:
                return SwiftTypeInfo(typeName: "String", needsEncoding: false)
        }
    }

    private static func parameterDocLine(schema: JSONSchema) -> String? {
        var parts: [String] = []
        if let description = schemaDescription(schema), !description.isEmpty {
            parts.append(description)
        }

        if case .enum(let values, _, _, _, _) = schema, !values.isEmpty {
            parts.append("Values: \(values.joined(separator: ", "))")
        }

        if parts.isEmpty {
            return nil
        }
        return parts.joined(separator: " ")
    }

    private static func schemaDescription(_ schema: JSONSchema) -> String? {
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
        }
    }

    private static func defaultValueLiteral(for schema: JSONSchema, typeInfo: SwiftTypeInfo) -> String? {
        guard let defaultValue = schemaDefaultValue(schema) else { return nil }
        let value = defaultValue.value
        if value is Void || value is NSNull {
            return "nil"
        }

        if typeInfo.needsEncoding {
            if let stringValue = value as? String {
                return encodedLiteral(for: typeInfo.typeName, value: stringValue)
            }
        }

        return swiftLiteral(from: value)
    }

    private static func schemaDefaultValue(_ schema: JSONSchema) -> AnyCodable? {
        switch schema {
        case .string(_, _, _, _, _, let defaultValue):
            return defaultValue
        case .number(_, _, _, _, let defaultValue):
            return defaultValue
        case .boolean(_, _, let defaultValue):
            return defaultValue
        case .array(_, _, _, let defaultValue):
            return defaultValue
        case .object(_, let defaultValue):
            return defaultValue
        case .enum(_, _, _, _, let defaultValue):
            return defaultValue
        }
    }

    private static func encodedLiteral(for typeName: String, value: String) -> String? {
        let escaped = escapeSwiftString(value)
        switch typeName {
        case "Date":
            return "ISO8601DateFormatter().date(from: \"\(escaped)\")!"
        case "URL":
            return "URL(string: \"\(escaped)\")!"
        case "UUID":
            return "UUID(uuidString: \"\(escaped)\")!"
        case "Data":
            return "Data(base64Encoded: \"\(escaped)\")!"
        default:
            return nil
        }
    }

    private static func swiftLiteral(from value: Any) -> String? {
        if let stringValue = value as? String {
            return "\"\(escapeSwiftString(stringValue))\""
        }
        if let boolValue = value as? Bool {
            return boolValue ? "true" : "false"
        }
        if let intValue = value as? Int {
            return "\(intValue)"
        }
        if let intValue = value as? Int64 {
            return "\(intValue)"
        }
        if let intValue = value as? UInt {
            return "\(intValue)"
        }
        if let doubleValue = value as? Double {
            return String(describing: doubleValue)
        }
        if let floatValue = value as? Float {
            return String(describing: floatValue)
        }
        if let arrayValue = value as? [Any] {
            var elements: [String] = []
            for element in arrayValue {
                guard let literal = swiftLiteral(from: element) else { return nil }
                elements.append(literal)
            }
            return "[\(elements.joined(separator: ", "))]"
        }
        if let arrayValue = value as? [AnyCodable] {
            var elements: [String] = []
            for element in arrayValue {
                guard let literal = swiftLiteral(from: element.value) else { return nil }
                elements.append(literal)
            }
            return "[\(elements.joined(separator: ", "))]"
        }
        if let dictValue = value as? [String: Any] {
            var pairs: [String] = []
            for (key, value) in dictValue {
                guard let literal = swiftLiteral(from: value) else { return nil }
                pairs.append("\"\(escapeSwiftString(key))\": \(literal)")
            }
            return "[\(pairs.joined(separator: ", "))]"
        }
        if let dictValue = value as? [String: AnyCodable] {
            var pairs: [String] = []
            for (key, value) in dictValue {
                guard let literal = swiftLiteral(from: value.value) else { return nil }
                pairs.append("\"\(escapeSwiftString(key))\": \(literal)")
            }
            return "[\(pairs.joined(separator: ", "))]"
        }
        return nil
    }

    private static func escapeSwiftString(_ value: String) -> String {
        var escaped = value
        escaped = escaped.replacingOccurrences(of: "\\", with: "\\\\")
        escaped = escaped.replacingOccurrences(of: "\"", with: "\\\"")
        escaped = escaped.replacingOccurrences(of: "\n", with: "\\n")
        escaped = escaped.replacingOccurrences(of: "\r", with: "\\r")
        escaped = escaped.replacingOccurrences(of: "\t", with: "\\t")
        return escaped
    }

    fileprivate static func pascalCase(_ string: String) -> String {
        let parts = string.split { !$0.isLetter && !$0.isNumber }
        let joined = parts.map { part -> String in
            guard let first = part.first else { return "" }
            return String(first).uppercased() + part.dropFirst()
        }.joined()
        return joined.isEmpty ? "MCPServer" : joined
    }

    fileprivate static func swiftIdentifier(from raw: String, lowerCamel: Bool) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if isValidIdentifier(trimmed) {
            return reservedKeywords.contains(trimmed) ? "\(trimmed)_" : trimmed
        }

        let parts = trimmed.split { !$0.isLetter && !$0.isNumber }
        if parts.isEmpty {
            return "value"
        }

        let first = String(parts[0])
        let rest = parts.dropFirst().map { part -> String in
            let value = String(part)
            guard let firstChar = value.first else { return value }
            return String(firstChar).uppercased() + value.dropFirst()
        }
        var combined = ([first] + rest).joined()

        if !lowerCamel, let firstChar = combined.first {
            combined = String(firstChar).uppercased() + combined.dropFirst()
        }

        if let firstChar = combined.first, firstChar.isNumber {
            combined = "_" + combined
        }

        if reservedKeywords.contains(combined) {
            combined += "_"
        }

        return combined
    }

    fileprivate static func isValidIdentifier(_ value: String) -> Bool {
        guard let first = value.first else {
            return false
        }
        guard first.isLetter || first == "_" else {
            return false
        }
        for character in value.dropFirst() {
            if !(character.isLetter || character.isNumber || character == "_") {
                return false
            }
        }
        return true
    }

    fileprivate static let reservedKeywords: Set<String> = [
        "associatedtype", "class", "deinit", "enum", "extension", "fileprivate",
        "func", "import", "init", "inout", "internal", "let", "open", "operator",
        "private", "protocol", "public", "static", "struct", "subscript", "typealias",
        "var", "break", "case", "continue", "default", "defer", "do", "else", "fallthrough",
        "for", "guard", "if", "in", "repeat", "return", "switch", "where", "while",
        "as", "catch", "false", "is", "nil", "rethrows", "super", "self", "Self",
        "throw", "throws", "true", "try", "Any"
    ]

    private static func buildReturnTypes(
        tools: [MCPTool],
        openapiReturnSchemas: [String: OpenAPIReturnInfo],
        registry: OpenAPITypeRegistry
    ) -> [String: OpenAPIReturnInfo] {
        var results: [String: OpenAPIReturnInfo] = [:]
        for tool in tools {
            guard let openapiInfo = openapiReturnSchemas[tool.name] else { continue }
            let baseName = "\(pascalCase(tool.name))Response"
            let typeName = registry.swiftType(for: openapiInfo.schema, suggestedName: baseName)
            results[tool.name] = OpenAPIReturnInfo(
                typeName: typeName,
                schema: openapiInfo.schema,
                description: openapiInfo.description
            )
        }
        return results
    }

    private static func returnLines(returnType: String) -> [String] {
        if returnType == "String" {
            return ["        return text"]
        }
        if returnType == "Void" {
            return [
                "        _ = try MCPClientResultDecoder.decode(Void.self, from: text)",
                "        return"
            ]
        }
        return ["        return try MCPClientResultDecoder.decode(\(returnType).self, from: text)"]
    }
}

public struct OpenAPIReturnInfo: Sendable {
    public let typeName: String
    public let schema: JSONSchema
    public let description: String?

    public init(typeName: String, schema: JSONSchema, description: String?) {
        self.typeName = typeName
        self.schema = schema
        self.description = description
    }
}

public enum OpenAPIProxyLoader {
    public static func loadReturnSchemas(from value: String?) async throws -> [String: OpenAPIReturnInfo] {
        guard let value, !value.isEmpty else { return [:] }
        let url = openAPIURL(from: value)
        let data: Data
        if url.isFileURL {
            data = try Data(contentsOf: url)
        } else {
            let (remoteData, _) = try await URLSession.shared.data(from: url)
            data = remoteData
        }

        let spec = try JSONDecoder().decode(OpenAPIProxySpec.self, from: data)
        return spec.returnSchemasByOperationId()
    }

    private static func openAPIURL(from value: String) -> URL {
        if let url = URL(string: value), url.scheme != nil {
            return url
        }
        return URL(fileURLWithPath: value)
    }
}

private struct OpenAPIProxySpec: Decodable {
    struct PathItem: Decodable {
        let post: Operation?
    }

    struct Operation: Decodable {
        let operationId: String?
        let description: String?
        let requestBody: RequestBody?
        let responses: [String: Response]
    }

    struct RequestBody: Decodable {
        let content: [String: MediaType]?
    }

    struct Response: Decodable {
        let description: String?
        let content: [String: MediaType]?
    }

    struct MediaType: Decodable {
        let schema: JSONSchema?
    }

    let paths: [String: PathItem]

    func returnSchemasByOperationId() -> [String: OpenAPIReturnInfo] {
        var results: [String: OpenAPIReturnInfo] = [:]
        for item in paths.values {
            guard let operation = item.post,
                  let operationId = operation.operationId else { continue }
            guard let response = pickResponse(operation.responses),
                  let schema = pickSchema(response.content) else { continue }
            results[operationId] = OpenAPIReturnInfo(
                typeName: "String",
                schema: schema,
                description: response.description
            )
        }
        return results
    }

    private func pickResponse(_ responses: [String: Response]) -> Response? {
        if let response = responses["200"] {
            return response
        }
        let twoHundreds = responses.keys.filter { $0.hasPrefix("2") }.sorted()
        if let key = twoHundreds.first {
            return responses[key]
        }
        return nil
    }

    private func pickSchema(_ content: [String: MediaType]?) -> JSONSchema? {
        guard let content else { return nil }
        if let schema = content["application/json"]?.schema {
            return schema
        }
        return content.values.first?.schema
    }
}

private final class OpenAPITypeRegistry {
    private var definitions: [String: String] = [:]
    private var usedNames: Set<String> = []

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
        case .enum(let values, _, let description, _, _):
            let enumName = uniqueName(suggestedName)
            ensureEnum(name: enumName, values: values, description: description)
            return enumName
        case .object(let object, _):
            if let knownType = knownSwiftMCPType(for: object) {
                return knownType
            }
            let structName = uniqueName(suggestedName)
            ensureStruct(name: structName, object: object)
            return structName
        }
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

    private func matchesStringSchema(_ schema: JSONSchema?) -> Bool {
        guard let schema else { return false }
        if case .string = schema {
            return true
        }
        return false
    }

    private func ensureStruct(name: String, object: JSONSchema.Object) {
        guard definitions[name] == nil else { return }

        var lines: [String] = []
        lines.append(contentsOf: docCommentLines(from: object.description, indent: ""))
        lines.append("public struct \(name): Codable, Sendable {")

        let sortedProperties = object.properties.keys.sorted()
        var codingKeys: [(swift: String, original: String)] = []

        for key in sortedProperties {
            guard let schema = object.properties[key] else { continue }
            let swiftName = ProxyGenerator.swiftIdentifier(from: key, lowerCamel: true)
            let typeName = swiftType(for: schema, suggestedName: "\(name)\(ProxyGenerator.pascalCase(key))")
            let isRequired = object.required.contains(key)
            let propertyType = isRequired ? typeName : "\(typeName)?"
            lines.append(contentsOf: docCommentLines(from: schemaDescription(schema), indent: "    "))
            lines.append("    public let \(swiftName): \(propertyType)")
            if swiftName != key {
                codingKeys.append((swift: swiftName, original: key))
            }
        }

        if !codingKeys.isEmpty {
            lines.append("")
            lines.append("    private enum CodingKeys: String, CodingKey {")
            for key in codingKeys {
                lines.append("        case \(key.swift) = \"\(key.original)\"")
            }
            lines.append("    }")
        }

        lines.append("}")
        definitions[name] = lines.joined(separator: "\n")
    }

    private func ensureEnum(name: String, values: [String], description: String?) {
        guard definitions[name] == nil else { return }
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

    private func uniqueName(_ name: String) -> String {
        if !usedNames.contains(name) {
            usedNames.insert(name)
            return name
        }
        var index = 2
        while usedNames.contains("\(name)\(index)") {
            index += 1
        }
        let result = "\(name)\(index)"
        usedNames.insert(result)
        return result
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
    }
}
}
