import Foundation
import SwiftMCP

extension ProxyGenerator {
    static func makePromptMethodLines(
        prompts: [Prompt],
        usedMethodNames: inout Set<String>
    ) -> [String] {
        let lines = [
            "    public func listPrompts() async throws -> [Prompt] {",
            "        try await proxy.listPrompts()",
            "    }",
            "",
            "    public func getPrompt(name: String, arguments: JSONDictionary = [:]) async throws -> PromptResult {",
            "        try await proxy.getPrompt(name: name, arguments: arguments)",
            "    }"
        ]

        return lines
    }

    static func makePromptWrapperLines(
        prompts: [Prompt],
        usedMethodNames: inout Set<String>
    ) -> [String] {
        var lines: [String] = []
        let sortedPrompts = prompts.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        for prompt in sortedPrompts {
            appendPromptWrapper(prompt: prompt, lines: &lines, usedMethodNames: &usedMethodNames)
        }

        return lines
    }

    private static func appendPromptWrapper(
        prompt: Prompt,
        lines: inout [String],
        usedMethodNames: inout Set<String>
    ) {
        guard let parameters = promptParameters(for: prompt) else {
            return
        }

        if !lines.isEmpty {
            lines.append("")
        }

        let methodName = uniqueMethodName(
            candidate: swiftIdentifier(from: prompt.name, lowerCamel: true),
            suffix: "Prompt",
            usedMethodNames: &usedMethodNames
        )
        let signature = parameters.map { $0.signature }.joined(separator: ", ")
        let description = prompt.description?.trimmingCharacters(in: .whitespacesAndNewlines)
        lines.append(contentsOf: wrapperDocCommentLines(description: description, parameters: parameters))
        lines.append("    public func \(methodName)(\(signature)) async throws -> PromptResult {")

        let escapedName = escapeSwiftString(prompt.name)
        if parameters.isEmpty {
            lines.append("        try await getPrompt(name: \"\(escapedName)\")")
            lines.append("    }")
            return
        }

        lines.append("        var arguments: JSONDictionary = [:]")
        for parameter in parameters {
            let key = parameter.originalName
            let encode = "try MCPClientArgumentEncoder.encode(\(parameter.swiftName))"
            if parameter.isOptional {
                lines.append("        if let \(parameter.swiftName) { arguments[\"\(key)\"] = \(encode) }")
            } else {
                lines.append("        arguments[\"\(key)\"] = \(encode)")
            }
        }
        lines.append("        return try await getPrompt(name: \"\(escapedName)\", arguments: arguments)")
        lines.append("    }")
    }

    static func promptParameters(for prompt: Prompt) -> [MethodParameter]? {
        var parameters: [MethodParameter] = []
        var seenSwiftNames: Set<String> = []

        for argument in prompt.arguments {
            guard let parameter = makePromptParameter(
                argument: argument,
                seenSwiftNames: &seenSwiftNames
            ) else {
                return nil
            }
            parameters.append(parameter)
        }

        return parameters
    }

    private static func makePromptParameter(
        argument: MCPParameterInfo,
        seenSwiftNames: inout Set<String>
    ) -> MethodParameter? {
        guard let typeInfo = swiftTypeInfo(for: argument.type) else {
            return nil
        }

        let swiftName = swiftIdentifier(from: argument.name, lowerCamel: true)
        guard seenSwiftNames.insert(swiftName).inserted else {
            return nil
        }

        let defaultLiteral = promptDefaultValueLiteral(for: argument.defaultValue, typeInfo: typeInfo)
        let isDefaultNil = defaultLiteral == "nil"
        let hasDefault = defaultLiteral != nil
        let isOptional = isDefaultNil || (!argument.isRequired && !hasDefault)
        let typeName = isOptional ? "\(typeInfo.typeName)?" : typeInfo.typeName

        let defaultValue: String
        if let defaultLiteral {
            defaultValue = " = \(defaultLiteral)"
        } else if isOptional {
            defaultValue = " = nil"
        } else {
            defaultValue = ""
        }

        return MethodParameter(
            originalName: argument.name,
            swiftName: swiftName,
            signature: "\(swiftName): \(typeName)\(defaultValue)",
            isOptional: isOptional,
            needsEncoding: typeInfo.needsEncoding,
            docLine: argument.description
        )
    }
}
