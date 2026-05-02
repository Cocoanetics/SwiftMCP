//
//  SwiftMCPAggregatorTool — main.swift
//
//  Scans target sources for `@MCPExtension([name])` extensions of @MCPServer
//  types and emits, per target:
//
//    1. A `SwiftMCPBootstrap_<Target>.register(in: server)` umbrella that
//       calls every `<Type>.<Name>.register(in: server)`.
//    2. An `extension <Type>.Client { … }` adding client-side methods for
//       every `@MCPTool` / `@MCPResource` / `@MCPPrompt` declared inside
//       the scanned extensions, mirroring what
//       `@MCPServer(generateClient: true)` emits for the primary type.
//
//  Member macros cannot emit extensions of arbitrary types, so the Client
//  surface for extension-defined methods is filled in by this build-plugin
//  pass instead.
//
//  CLI:
//    SwiftMCPAggregatorTool --module <ModuleName> --output <path> [<input.swift> ...]
//

import Foundation
import SwiftSyntax
import SwiftParser

// MARK: - CLI

struct ToolArgs {
    var moduleName: String
    var outputPath: String
    var inputs: [String]
}

func parseArgs(_ argv: [String]) -> ToolArgs {
    var moduleName = ""
    var outputPath = ""
    var inputs: [String] = []
    var i = 1
    while i < argv.count {
        let arg = argv[i]
        switch arg {
        case "--module":
            i += 1
            moduleName = argv[i]
        case "--output":
            i += 1
            outputPath = argv[i]
        default:
            inputs.append(arg)
        }
        i += 1
    }
    return ToolArgs(moduleName: moduleName, outputPath: outputPath, inputs: inputs)
}

// MARK: - Models

enum ContributionKind {
    case tool(wireName: String)
    case resource(templates: [String])
    case prompt
}

struct DiscoveredParameter {
    var name: String
    var label: String
    var typeString: String
    var defaultValue: String?
    var isOptional: Bool
}

struct DiscoveredMethod {
    var kind: ContributionKind
    var functionName: String
    var parameters: [DiscoveredParameter]
    var returnTypeString: String?
    var isAsync: Bool
    var isThrowing: Bool
    var throwsKeyword: String?
    var docComment: String?
    var paramDocs: [String: String]
    var returnsDoc: String?
}

struct DiscoveredExtension {
    var extendedType: String
    var name: String
    var methods: [DiscoveredMethod]
}

// MARK: - Visitor

final class ExtensionFinder: SyntaxVisitor {
    var extensions: [DiscoveredExtension] = []
    var imports: Set<String> = []
    var currentFilePath: String = ""

    override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
        let path = node.path.map { $0.name.text }.joined(separator: ".")
        if !path.isEmpty { imports.insert(path) }
        return .skipChildren
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        // Find @MCPExtension on this extension.
        var hasMarker = false
        var explicitName: String?
        for attr in node.attributes {
            guard let attrSyntax = attr.as(AttributeSyntax.self),
                  let id = attrSyntax.attributeName.as(IdentifierTypeSyntax.self),
                  id.name.text == "MCPExtension" else { continue }
            hasMarker = true
            if let argList = attrSyntax.arguments?.as(LabeledExprListSyntax.self),
               let firstArg = argList.first,
               let lit = firstArg.expression.as(StringLiteralExprSyntax.self) {
                explicitName = lit.segments.description
            }
            break
        }
        guard hasMarker else { return .visitChildren }

        let resolvedName = explicitName ?? deriveNameFromFilename(currentFilePath)
        guard !resolvedName.isEmpty else { return .visitChildren }

        let extendedType = node.extendedType.trimmedDescription

        // Collect methods.
        var methods: [DiscoveredMethod] = []
        for member in node.memberBlock.members {
            guard let funcDecl = member.decl.as(FunctionDeclSyntax.self) else { continue }
            for attr in funcDecl.attributes {
                guard let attrSyntax = attr.as(AttributeSyntax.self),
                      let id = attrSyntax.attributeName.as(IdentifierTypeSyntax.self) else { continue }

                let kind: ContributionKind?
                switch id.name.text {
                case "MCPTool":
                    var wire = funcDecl.name.text
                    if let argList = attrSyntax.arguments?.as(LabeledExprListSyntax.self) {
                        for a in argList where a.label?.text == "name" {
                            if let lit = a.expression.as(StringLiteralExprSyntax.self) {
                                wire = lit.segments.description
                            }
                        }
                    }
                    kind = .tool(wireName: wire)
                case "MCPResource":
                    var templates: [String] = []
                    if let argList = attrSyntax.arguments?.as(LabeledExprListSyntax.self) {
                        for a in argList where a.label == nil {
                            if let lit = a.expression.as(StringLiteralExprSyntax.self) {
                                templates.append(lit.segments.description)
                            } else if let arr = a.expression.as(ArrayExprSyntax.self) {
                                for el in arr.elements {
                                    if let lit = el.expression.as(StringLiteralExprSyntax.self) {
                                        templates.append(lit.segments.description)
                                    }
                                }
                            }
                        }
                    }
                    kind = .resource(templates: templates)
                case "MCPPrompt":
                    kind = .prompt
                default:
                    kind = nil
                }
                guard let resolvedKind = kind else { continue }

                methods.append(extractMethod(funcDecl: funcDecl, kind: resolvedKind))
                break
            }
        }

        extensions.append(DiscoveredExtension(extendedType: extendedType, name: resolvedName, methods: methods))
        return .visitChildren
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
        return DiscoveredParameter(name: name, label: label, typeString: typeString, defaultValue: defaultValue, isOptional: isOptional)
    }
    let returnType = funcDecl.signature.returnClause?.type.trimmedDescription
    let isAsync = funcDecl.signature.effectSpecifiers?.asyncSpecifier != nil
    let throwsClause = funcDecl.signature.effectSpecifiers?.throwsClause
    let throwsKeyword = throwsClause?.trimmedDescription
    let isThrowing = throwsClause != nil
    let (doc, paramDocs, returnsDoc) = parseDocComment(trivia: funcDecl.leadingTrivia)
    return DiscoveredMethod(
        kind: kind,
        functionName: funcDecl.name.text,
        parameters: parameters,
        returnTypeString: returnType,
        isAsync: isAsync,
        isThrowing: isThrowing,
        throwsKeyword: throwsKeyword,
        docComment: doc,
        paramDocs: paramDocs,
        returnsDoc: returnsDoc
    )
}

// MARK: - Doc-comment parsing (best-effort)

func parseDocComment(trivia: Trivia) -> (description: String?, params: [String: String], returns: String?) {
    var lines: [String] = []
    for piece in trivia.pieces {
        switch piece {
        case .docLineComment(let raw):
            var line = raw
            if line.hasPrefix("///") { line.removeFirst(3) }
            lines.append(line.trimmingCharacters(in: .whitespaces))
        case .docBlockComment(let raw):
            var stripped = raw
            if stripped.hasPrefix("/**") { stripped.removeFirst(3) }
            if stripped.hasSuffix("*/") { stripped.removeLast(2) }
            for sub in stripped.split(separator: "\n", omittingEmptySubsequences: false) {
                var line = sub.trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("*") { line.removeFirst() }
                lines.append(line.trimmingCharacters(in: .whitespaces))
            }
        default:
            break
        }
    }

    var description: [String] = []
    var params: [String: String] = [:]
    var returns: String?
    for line in lines {
        if line.hasPrefix("- Parameter ") {
            let body = String(line.dropFirst("- Parameter ".count))
            if let colonIdx = body.firstIndex(of: ":") {
                let name = body[..<colonIdx].trimmingCharacters(in: .whitespaces)
                let desc = body[body.index(after: colonIdx)...].trimmingCharacters(in: .whitespaces)
                params[name] = desc
            }
        } else if line.hasPrefix("- Returns:") {
            returns = String(line.dropFirst("- Returns:".count)).trimmingCharacters(in: .whitespaces)
        } else if line.hasPrefix("- Throws:") {
            // ignored
        } else {
            description.append(line)
        }
    }

    let descText = description.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    return (descText.isEmpty ? nil : descText, params, returns)
}

// MARK: - Naming derivation (kept in sync with MCPExtensionNaming in the macros target)

func deriveNameFromFilename(_ filePath: String) -> String {
    let basename: String
    if let slashIdx = filePath.lastIndex(of: "/") {
        basename = String(filePath[filePath.index(after: slashIdx)...])
    } else {
        basename = filePath
    }
    var stem = basename
    if stem.hasSuffix(".swift") { stem = String(stem.dropLast(".swift".count)) }
    if let plusIdx = stem.lastIndex(of: "+") {
        stem = String(stem[stem.index(after: plusIdx)...])
    }
    return sanitizeIdentifier(stem)
}

func sanitizeIdentifier(_ s: String) -> String {
    guard !s.isEmpty else { return "Extension" }
    var out = ""
    var first = true
    for ch in s {
        if first {
            if ch.isLetter || ch == "_" { out.append(ch) } else { out.append("_") }
            first = false
        } else {
            if ch.isLetter || ch.isNumber || ch == "_" { out.append(ch) } else { out.append("_") }
        }
    }
    return out.isEmpty ? "Extension" : out
}

func sanitize(_ s: String) -> String { sanitizeIdentifier(s) }

// MARK: - Codegen

func generateOutput(moduleName: String, extensions: [DiscoveredExtension], imports: Set<String>) -> String {
    var out = ""
    out.append("// Generated by SwiftMCPAggregatorTool — DO NOT EDIT.\n")
    out.append("// Bootstrap umbrella + Client extensions for module \(moduleName).\n\n")

    var importsToEmit = imports
    importsToEmit.insert("SwiftMCP")
    importsToEmit.remove(moduleName)
    for imp in importsToEmit.sorted() {
        out.append("import \(imp)\n")
    }
    out.append("\n")

    out.append(generateUmbrella(moduleName: moduleName, extensions: extensions))
    out.append("\n\n")
    out.append(generateClientExtensions(extensions: extensions))
    return out
}

func generateUmbrella(moduleName: String, extensions: [DiscoveredExtension]) -> String {
    var out = ""
    out.append("public enum SwiftMCPBootstrap_\(sanitize(moduleName)) {\n")

    if extensions.isEmpty {
        out.append("    // no @MCPExtension declarations found in this target\n")
    } else {
        let grouped = Dictionary(grouping: extensions, by: \.extendedType)
        for type in grouped.keys.sorted() {
            let exts = grouped[type] ?? []
            out.append("    /// Registers all `@MCPExtension` contributions to `\(type)` from this module.\n")
            out.append("    public static func register(in server: \(type)) {\n")
            for ext in exts.sorted(by: { $0.name < $1.name }) {
                out.append("        \(type).\(ext.name).register(in: server)\n")
            }
            out.append("    }\n")
        }
    }

    out.append("}\n")
    return out
}

func generateClientExtensions(extensions: [DiscoveredExtension]) -> String {
    let grouped = Dictionary(grouping: extensions, by: \.extendedType)
    var out = ""
    for type in grouped.keys.sorted() {
        let exts = grouped[type] ?? []
        let allMethods = exts.flatMap(\.methods)
        guard !allMethods.isEmpty else { continue }

        out.append("extension \(type).Client {\n")
        for method in allMethods {
            out.append("\n")
            out.append(emitClientMethod(method))
        }
        out.append("}\n\n")
    }
    return out
}

// MARK: - Per-method emission

func emitClientMethod(_ method: DiscoveredMethod) -> String {
    switch method.kind {
    case .tool(let wireName):
        return emitToolClientMethod(method, wireToolName: wireName)
    case .resource(let templates):
        return emitResourceClientMethod(method, templates: templates)
    case .prompt:
        return emitPromptClientMethod(method)
    }
}

func emitToolClientMethod(_ method: DiscoveredMethod, wireToolName: String) -> String {
    var out = ""
    out.append(docCommentBlock(method))

    let signature = method.parameters.map(parameterSignature).joined(separator: ", ")
    let effects = effectSpecifiers(isAsync: method.isAsync, throwsKeyword: method.throwsKeyword ?? "throws")
    let hasReturn = method.returnTypeString != nil && method.returnTypeString != "Void"
    let returnTypeText = method.returnTypeString.map { "\($0).MCPClientReturn" }
    let returnClause = hasReturn ? " -> \(returnTypeText!)" : ""
    let hasParams = !method.parameters.isEmpty

    out.append("    public func \(method.functionName)(\(signature))\(effects)\(returnClause) {\n")
    out.append(encodedArgumentsLines(parameters: method.parameters, indent: "        "))

    let argumentsName: String
    if hasParams && !method.isAsync {
        out.append("        let capturedArguments = arguments\n")
        argumentsName = "capturedArguments"
    } else if hasParams {
        argumentsName = "arguments"
    } else {
        argumentsName = ""
    }

    let call = hasParams
        ? "proxy.callTool(\"\(wireToolName)\", arguments: \(argumentsName))"
        : "proxy.callTool(\"\(wireToolName)\")"
    let invocation: String = method.isAsync
        ? "try await \(call)"
        : "try MCPClientBlocking.call { try await \(call) }"
    out.append("        let text = \(invocation)\n")

    if hasReturn {
        out.append("        return try MCPClientResultDecoder.decode(\(returnTypeText!).self, from: text)\n")
    } else {
        out.append("        _ = try MCPClientResultDecoder.decode(Void.self, from: text)\n")
        out.append("        return\n")
    }

    out.append("    }\n")
    return out
}

func emitResourceClientMethod(_ method: DiscoveredMethod, templates: [String]) -> String {
    var out = ""
    out.append(docCommentBlock(method))

    let signature = method.parameters.map(parameterSignature).joined(separator: ", ")
    let effects = effectSpecifiers(isAsync: method.isAsync, throwsKeyword: method.throwsKeyword ?? "throws")
    let hasReturn = method.returnTypeString != nil && method.returnTypeString != "Void"
    let returnText = method.returnTypeString.map { "\($0).MCPClientReturn" }
    let returnClause = hasReturn ? " -> \(returnText!)" : ""
    let hasParams = !method.parameters.isEmpty

    out.append("    public func \(method.functionName)(\(signature))\(effects)\(returnClause) {\n")
    out.append(encodedArgumentsLines(parameters: method.parameters, indent: "        "))

    let argumentsName: String
    if hasParams && !method.isAsync {
        out.append("        let capturedArguments = arguments\n")
        argumentsName = "capturedArguments"
    } else if hasParams {
        argumentsName = "arguments"
    } else {
        argumentsName = "[:]"
    }

    let ordered = templates.sorted { resourceTemplateVariableCount($0) > resourceTemplateVariableCount($1) }

    if ordered.count <= 1 {
        let template = ordered.first ?? ""
        out.append("        let uri = try \"\(template.replacingOccurrences(of: "\"", with: "\\\""))\".constructURI(with: \(argumentsName))\n")
    } else {
        out.append("        let uri: URL\n")
        for (idx, template) in ordered.enumerated() {
            let vars = resourceTemplateVariables(in: template)
            let cond = vars.isEmpty ? "true" : vars.map { "\(argumentsName)[\"\($0)\"] != nil" }.joined(separator: " && ")
            let keyword = idx == 0 ? "if" : "else if"
            out.append("        \(keyword) \(cond) {\n")
            out.append("            uri = try \"\(template.replacingOccurrences(of: "\"", with: "\\\""))\".constructURI(with: \(argumentsName))\n")
            out.append("        }\n")
        }
        out.append("        else {\n")
        out.append("            throw MCPServerProxyError.communicationError(\"No resource template matched for \(method.functionName)\")\n")
        out.append("        }\n")
    }

    let readCall: String = method.isAsync
        ? "try await proxy.readResource(uri: uri)"
        : "try MCPClientBlocking.call { try await proxy.readResource(uri: uri) }"
    out.append("        let contents = \(readCall)\n")

    let returnType = method.returnTypeString ?? "Void"
    if !hasReturn {
        out.append("        return\n")
    } else if returnType == "MCPResourceContent" || returnType == "GenericResourceContent" {
        out.append("        guard let content = contents.first else {\n")
        out.append("            throw MCPServerProxyError.communicationError(\"Resource \(method.functionName) returned no content\")\n")
        out.append("        }\n")
        out.append("        return content\n")
    } else if returnType == "[MCPResourceContent]" || returnType == "[GenericResourceContent]" {
        out.append("        return contents\n")
    } else if returnType == "Data" {
        out.append("        if let blob = contents.first?.blob { return blob }\n")
        out.append("        if let text = contents.first?.text {\n")
        out.append("            return try MCPClientResultDecoder.decode(Data.self, from: text)\n")
        out.append("        }\n")
        out.append("        throw MCPServerProxyError.communicationError(\"Resource \(method.functionName) returned no blob content\")\n")
    } else {
        out.append("        guard let text = contents.first?.text else {\n")
        out.append("            throw MCPServerProxyError.communicationError(\"Resource \(method.functionName) returned no text content\")\n")
        out.append("        }\n")
        out.append("        return try MCPClientResultDecoder.decode(\(returnText!).self, from: text)\n")
    }

    out.append("    }\n")
    return out
}

func emitPromptClientMethod(_ method: DiscoveredMethod) -> String {
    var out = ""
    out.append(docCommentBlock(method))

    let signature = method.parameters.map(parameterSignature).joined(separator: ", ")
    let effects = effectSpecifiers(isAsync: method.isAsync, throwsKeyword: method.throwsKeyword ?? "throws")
    let hasParams = !method.parameters.isEmpty

    out.append("    public func \(method.functionName)(\(signature))\(effects) -> PromptResult {\n")
    out.append(encodedArgumentsLines(parameters: method.parameters, indent: "        "))

    let argumentsName: String
    if hasParams && !method.isAsync {
        out.append("        let capturedArguments = arguments\n")
        argumentsName = "capturedArguments"
    } else if hasParams {
        argumentsName = "arguments"
    } else {
        argumentsName = ""
    }

    let call = hasParams
        ? "proxy.getPrompt(name: \"\(method.functionName)\", arguments: \(argumentsName))"
        : "proxy.getPrompt(name: \"\(method.functionName)\")"
    let invocation: String = method.isAsync
        ? "return try await \(call)"
        : "return try MCPClientBlocking.call { try await \(call) }"
    out.append("        \(invocation)\n")
    out.append("    }\n")
    return out
}

// MARK: - Codegen helpers

func parameterSignature(_ p: DiscoveredParameter) -> String {
    let label: String
    if p.label == "_" {
        label = "_ \(p.name)"
    } else if p.label != p.name {
        label = "\(p.label) \(p.name)"
    } else {
        label = p.name
    }
    var sig = "\(label): \(p.typeString)"
    if let dv = p.defaultValue, !dv.isEmpty { sig += " = \(dv)" }
    return sig
}

func effectSpecifiers(isAsync: Bool, throwsKeyword: String) -> String {
    var parts: [String] = []
    if isAsync { parts.append("async") }
    parts.append(throwsKeyword)
    return " " + parts.joined(separator: " ")
}

func encodedArgumentsLines(parameters: [DiscoveredParameter], indent: String) -> String {
    guard !parameters.isEmpty else { return "" }
    var out = "\(indent)var arguments: JSONDictionary = [:]\n"
    for p in parameters {
        let encode = "try MCPClientArgumentEncoder.encode(\(p.name))"
        if p.isOptional {
            out.append("\(indent)if let \(p.name) { arguments[\"\(p.name)\"] = \(encode) }\n")
        } else {
            out.append("\(indent)arguments[\"\(p.name)\"] = \(encode)\n")
        }
    }
    return out
}

func docCommentBlock(_ method: DiscoveredMethod) -> String {
    var lines: [String] = []
    if let doc = method.docComment, !doc.isEmpty {
        for line in doc.split(separator: "\n") {
            lines.append(String(line))
        }
    }
    for p in method.parameters {
        if let pd = method.paramDocs[p.name], !pd.isEmpty {
            lines.append("- Parameter \(p.name): \(pd)")
        }
    }
    if let r = method.returnsDoc, !r.isEmpty {
        lines.append("- Returns: \(r)")
    }
    guard !lines.isEmpty else { return "" }
    var out = "    /**\n"
    for l in lines { out.append("     \(l)\n") }
    out.append("     */\n")
    return out
}

func resourceTemplateVariables(in template: String) -> [String] {
    guard let regex = try? NSRegularExpression(pattern: "\\{[^}]+\\}") else { return [] }
    let nsRange = NSRange(template.startIndex..., in: template)
    var vars: [String] = []
    for match in regex.matches(in: template, range: nsRange) {
        guard let range = Range(match.range, in: template) else { continue }
        var expr = String(template[range].dropFirst().dropLast())
        if let first = expr.first, "+#./;?&".contains(first) { expr.removeFirst() }
        for spec in expr.split(separator: ",") {
            var name = String(spec)
            if let star = name.firstIndex(of: "*") { name = String(name[..<star]) }
            if let colon = name.firstIndex(of: ":") { name = String(name[..<colon]) }
            if !name.isEmpty, !vars.contains(name) { vars.append(name) }
        }
    }
    return vars
}

func resourceTemplateVariableCount(_ template: String) -> Int {
    resourceTemplateVariables(in: template).count
}

// MARK: - Driver

let args = parseArgs(CommandLine.arguments)
guard !args.moduleName.isEmpty, !args.outputPath.isEmpty else {
    FileHandle.standardError.write(Data("SwiftMCPAggregatorTool: --module and --output are required\n".utf8))
    exit(1)
}

let finder = ExtensionFinder(viewMode: .sourceAccurate)
for path in args.inputs {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
          let source = String(data: data, encoding: .utf8) else { continue }
    finder.currentFilePath = path
    let tree = Parser.parse(source: source)
    finder.walk(tree)
}

let generated = generateOutput(moduleName: args.moduleName, extensions: finder.extensions, imports: finder.imports)
let outURL = URL(fileURLWithPath: args.outputPath)
try? FileManager.default.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
try generated.write(to: outURL, atomically: true, encoding: .utf8)
