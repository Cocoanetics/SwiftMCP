import Foundation
import SwiftMCP

extension ProxyGenerator {
    static func makeMethodLines(
        tool: MCPTool,
        returnInfo: OpenAPIReturnInfo?,
        functionNaming: FunctionNaming = .lowerCamelCase
    ) -> [String] {
        var lines: [String] = []
        let methodName = toolMethodName(for: tool, functionNaming: functionNaming)
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

        lines.append("        var arguments: JSONDictionary = [:]")
        for param in parameters {
            let key = param.originalName
            let encode = "try MCPClientArgumentEncoder.encode(\(param.swiftName))"
            if param.isOptional {
                lines.append("        if let \(param.swiftName) { arguments[\"\(key)\"] = \(encode) }")
            } else {
                lines.append("        arguments[\"\(key)\"] = \(encode)")
            }
        }
        lines.append("        let text = try await proxy.callTool(\"\(tool.name)\", arguments: arguments)")
        lines.append(contentsOf: returnLines(returnType: returnType))
        lines.append("    }")
        return lines
    }

    private static func toolMethodName(for tool: MCPTool, functionNaming: FunctionNaming) -> String {
        let rawName = swiftIdentifier(from: tool.name, lowerCamel: true)
        let converted: String
        switch functionNaming {
        case .verbatim:
            converted = rawName
        case .lowerCamelCase:
            converted = NamingConverter.toLowerCamelCase(rawName)
        case .snakeCase:
            converted = NamingConverter.toSnakeCase(rawName)
        }
        // Re-sanitize after conversion (e.g., tool "class" → "class_" → "class" needs escaping again)
        return reservedKeywords.contains(converted) ? "`\(converted)`" : converted
    }

    static func methodParameters(for tool: MCPTool) -> [MethodParameter] {
        guard case .object(let object, _) = tool.inputSchema else {
            return []
        }

        let required = Set(object.required)
        let sortedKeys = object.properties.keys.sorted()
        return sortedKeys.compactMap { key in
            guard let schema = object.properties[key] else {
                return nil
            }
            return makeMethodParameter(key: key, schema: schema, required: required)
        }
    }

    private static func makeMethodParameter(
        key: String,
        schema: JSONSchema,
        required: Set<String>
    ) -> MethodParameter {
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

    static func docCommentLines(
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

        for bodyLine in bodyLines {
            lines.append("    /// \(bodyLine)")
        }
        return lines
    }

    static func parameterDocLine(schema: JSONSchema) -> String? {
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

    static func schemaDescription(_ schema: JSONSchema) -> String? {
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

    static func returnLines(returnType: String) -> [String] {
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
