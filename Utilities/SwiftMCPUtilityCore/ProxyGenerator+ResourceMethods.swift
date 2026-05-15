import Foundation
import SwiftMCP

extension ProxyGenerator {
    static func makeResourceMethodLines(
        resources: [SimpleResource],
        resourceTemplates: [SimpleResourceTemplate],
        usedMethodNames: inout Set<String>
    ) -> [String] {
        let lines = [
            "    public func listResources() async throws -> [SimpleResource] {",
            "        try await proxy.listResources()",
            "    }",
            "",
            "    public func listResourceTemplates() async throws -> [SimpleResourceTemplate] {",
            "        try await proxy.listResourceTemplates()",
            "    }",
            "",
            "    public func readResource(uri: URL) async throws -> [GenericResourceContent] {",
            "        try await proxy.readResource(uri: uri)",
            "    }"
        ]

        return lines
    }

    static func makeResourceWrapperLines(
        resources: [SimpleResource],
        resourceTemplates: [SimpleResourceTemplate],
        usedMethodNames: inout Set<String>
    ) -> [String] {
        var lines: [String] = []

        let sortedResources = sortedResources(resources)

        for resource in sortedResources {
            appendStaticResourceMethod(
                resource: resource,
                lines: &lines,
                usedMethodNames: &usedMethodNames
            )
        }

        let uniqueTemplates = uniqueResourceTemplates(resourceTemplates)
        for template in uniqueTemplates {
            appendTemplateResourceMethod(
                template: template,
                lines: &lines,
                usedMethodNames: &usedMethodNames
            )
        }

        return lines
    }

    private static func sortedResources(_ resources: [SimpleResource]) -> [SimpleResource] {
        resources.sorted {
            let nameOrder = $0.name.localizedCaseInsensitiveCompare($1.name)
            if nameOrder == .orderedSame {
                return $0.uri.absoluteString < $1.uri.absoluteString
            }
            return nameOrder == .orderedAscending
        }
    }

    private static func appendStaticResourceMethod(
        resource: SimpleResource,
        lines: inout [String],
        usedMethodNames: inout Set<String>
    ) {
        if !lines.isEmpty {
            lines.append("")
        }

        let methodName = uniqueMethodName(
            candidate: swiftIdentifier(from: resource.name, lowerCamel: true),
            suffix: "Resource",
            usedMethodNames: &usedMethodNames
        )
        let description = resource.description.trimmingCharacters(in: .whitespacesAndNewlines)
        lines.append(contentsOf: wrapperDocCommentLines(
            description: description.isEmpty ? nil : description,
            parameters: []
        ))
        lines.append("    public func \(methodName)() async throws -> [GenericResourceContent] {")
        let escapedURI = escapeSwiftString(resource.uri.absoluteString)
        lines.append("        try await readResource(uri: URL(string: \"\(escapedURI)\")!)")
        lines.append("    }")
    }

    private static func appendTemplateResourceMethod(
        template: SimpleResourceTemplate,
        lines: inout [String],
        usedMethodNames: inout Set<String>
    ) {
        guard let parameters = resourceTemplateParameters(for: template.uriTemplate) else {
            return
        }

        if !lines.isEmpty {
            lines.append("")
        }

        let methodName = uniqueMethodName(
            candidate: swiftIdentifier(from: template.name, lowerCamel: true),
            suffix: "Resource",
            usedMethodNames: &usedMethodNames
        )
        let description = template.description?.trimmingCharacters(in: .whitespacesAndNewlines)
        let signature = parameters.map { $0.signature }.joined(separator: ", ")
        lines.append(contentsOf: wrapperDocCommentLines(description: description, parameters: parameters))
        lines.append("    public func \(methodName)(\(signature)) async throws -> [GenericResourceContent] {")
        appendTemplateURIConstruction(template: template, parameters: parameters, lines: &lines)
        lines.append("        return try await readResource(uri: uri)")
        lines.append("    }")
    }

    private static func appendTemplateURIConstruction(
        template: SimpleResourceTemplate,
        parameters: [MethodParameter],
        lines: inout [String]
    ) {
        let escapedTemplate = escapeSwiftString(template.uriTemplate)
        if parameters.isEmpty {
            lines.append("        let uri = try \"\(escapedTemplate)\".constructURI(with: [:])")
            return
        }

        lines.append("        var uriParameters: JSONDictionary = [:]")
        for parameter in parameters {
            let key = parameter.originalName
            let encode = "try MCPClientArgumentEncoder.encode(\(parameter.swiftName))"
            if parameter.isOptional {
                lines.append("        if let \(parameter.swiftName) { uriParameters[\"\(key)\"] = \(encode) }")
            } else {
                lines.append("        uriParameters[\"\(key)\"] = \(encode)")
            }
        }
        lines.append("        let uri = try \"\(escapedTemplate)\".constructURI(with: uriParameters)")
    }

    static func uniqueResourceTemplates(_ templates: [SimpleResourceTemplate]) -> [SimpleResourceTemplate] {
        var seen: Set<String> = []
        var unique: [SimpleResourceTemplate] = []

        for template in templates {
            let key = "\(template.name)\u{0}\(template.uriTemplate)"
            if seen.insert(key).inserted {
                unique.append(template)
            }
        }

        return unique.sorted {
            let nameOrder = $0.name.localizedCaseInsensitiveCompare($1.name)
            if nameOrder == .orderedSame {
                return $0.uriTemplate < $1.uriTemplate
            }
            return nameOrder == .orderedAscending
        }
    }

    static func resourceTemplateParameters(for template: String) -> [MethodParameter]? {
        guard let regex = try? NSRegularExpression(pattern: #"\{[^}]+\}"#) else {
            return nil
        }

        let range = NSRange(template.startIndex..., in: template)
        let matches = regex.matches(in: template, range: range)
        if matches.isEmpty {
            return []
        }

        var parameters: [MethodParameter] = []
        var seenOriginalNames: Set<String> = []
        var seenSwiftNames: Set<String> = []

        for match in matches {
            guard let swiftRange = Range(match.range, in: template) else {
                continue
            }

            let expression = String(template[swiftRange])
            guard let variables = templateVariables(
                in: expression,
                template: template,
                expressionStart: swiftRange.lowerBound
            ) else {
                return nil
            }

            for variable in variables {
                if !seenOriginalNames.insert(variable.name).inserted {
                    continue
                }

                guard let parameter = makeTemplateParameter(
                    variable: variable,
                    seenSwiftNames: &seenSwiftNames
                ) else {
                    return nil
                }
                parameters.append(parameter)
            }
        }

        return parameters
    }

    private static func makeTemplateParameter(
        variable: TemplateVariable,
        seenSwiftNames: inout Set<String>
    ) -> MethodParameter? {
        let swiftName = swiftIdentifier(from: variable.name, lowerCamel: true)
        guard seenSwiftNames.insert(swiftName).inserted else {
            return nil
        }

        let signature: String
        if variable.isOptional {
            signature = "\(swiftName): String? = nil"
        } else {
            signature = "\(swiftName): String"
        }

        let docLine = variable.isOptional
            ? "Optional value for the `\(variable.name)` URI variable."
            : "Value for the `\(variable.name)` URI variable."
        return MethodParameter(
            originalName: variable.name,
            swiftName: swiftName,
            signature: signature,
            isOptional: variable.isOptional,
            needsEncoding: false,
            docLine: docLine
        )
    }

    static func templateVariables(
        in expression: String,
        template: String,
        expressionStart: String.Index
    ) -> [TemplateVariable]? {
        guard expression.first == "{", expression.last == "}" else {
            return nil
        }

        var content = String(expression.dropFirst().dropLast())
        var usesOptionalExpansion = false
        if let first = content.first, "+#./;?&".contains(first) {
            usesOptionalExpansion = first == "?" || first == "&" || first == ";"
            content.removeFirst()
        }

        let isQueryParameter = expressionAppearsInQuery(template: template, expressionStart: expressionStart)
        let variableSpecs = content.split(separator: ",", omittingEmptySubsequences: true)
        guard !variableSpecs.isEmpty else {
            return nil
        }

        var variables: [TemplateVariable] = []
        for spec in variableSpecs {
            let variable = String(spec).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !variable.isEmpty else {
                return nil
            }

            if variable.hasSuffix("*") || variable.contains(":") {
                return nil
            }

            variables.append(TemplateVariable(
                name: variable,
                isOptional: usesOptionalExpansion || isQueryParameter
            ))
        }

        return variables
    }

    static func expressionAppearsInQuery(template: String, expressionStart: String.Index) -> Bool {
        let prefix = template[..<expressionStart]
        let fragmentIndex = prefix.lastIndex(of: "#")

        if let ampersandIndex = prefix.lastIndex(of: "&"),
           fragmentIndex == nil || ampersandIndex > fragmentIndex! {
            return true
        }

        if let queryIndex = prefix.lastIndex(of: "?"),
           fragmentIndex == nil || queryIndex > fragmentIndex! {
            return true
        }

        return false
    }
}
