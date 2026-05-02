//
//  SwiftMCPAggregatorTool — main.swift
//
//  Reads Swift source files, finds `@MCPExtensionTool` functions inside
//  extensions of MCPServer types, and emits a single Swift file containing
//  a `SwiftMCPBootstrap_<ModuleName>.register()` function that pushes those
//  tools into `MCPExtensionRegistry`.
//
//  Invoked by the SwiftMCPAggregator build-tool plugin.
//
//  CLI:
//    SwiftMCPAggregatorTool --module <ModuleName> --output <path> [<input.swift> ...]
//

import Foundation
import SwiftSyntax
import SwiftParser

// MARK: - Argument parsing

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

// MARK: - Model

struct DiscoveredParameter {
    var name: String           // internal name
    var label: String          // external label ("_" if unlabeled)
    var typeString: String     // e.g. "Int", "String?"
    var isOptional: Bool
    var defaultValue: String?  // raw source text, if any
}

struct DiscoveredTool {
    var extendedType: String
    var functionName: String
    var wireName: String
    var description: String?
    var parameters: [DiscoveredParameter]
    var returnTypeString: String  // "Void" if absent
    var isAsync: Bool
    var isThrowing: Bool
}

// MARK: - Visitor

final class ExtensionToolFinder: SyntaxVisitor {
    var tools: [DiscoveredTool] = []
    var imports: Set<String> = []

    private var extendedTypeStack: [String] = []

    override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
        let path = node.path.map { $0.name.text }.joined(separator: ".")
        if !path.isEmpty { imports.insert(path) }
        return .skipChildren
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        let typeName = node.extendedType.trimmedDescription
        extendedTypeStack.append(typeName)
        return .visitChildren
    }

    override func visitPost(_ node: ExtensionDeclSyntax) {
        _ = extendedTypeStack.popLast()
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let extendedType = extendedTypeStack.last else { return .visitChildren }

        // Find @MCPExtensionTool attribute
        var hasMarker = false
        var customName: String?
        var explicitDescription: String?
        for attr in node.attributes {
            guard let attrSyntax = attr.as(AttributeSyntax.self),
                  let identifier = attrSyntax.attributeName.as(IdentifierTypeSyntax.self),
                  identifier.name.text == "MCPExtensionTool" else { continue }
            hasMarker = true
            if let argList = attrSyntax.arguments?.as(LabeledExprListSyntax.self) {
                for arg in argList {
                    if arg.label?.text == "name",
                       let lit = arg.expression.as(StringLiteralExprSyntax.self) {
                        customName = lit.segments.description
                    } else if arg.label?.text == "description",
                              let lit = arg.expression.as(StringLiteralExprSyntax.self) {
                        explicitDescription = lit.segments.description
                    }
                }
            }
        }
        guard hasMarker else { return .visitChildren }

        let funcName = node.name.text
        let parameters = node.signature.parameterClause.parameters.map { param -> DiscoveredParameter in
            let name = param.secondName?.text ?? param.firstName.text
            let label = param.firstName.text
            let typeString = param.type.trimmedDescription
            let isOptional = typeString.hasSuffix("?") || param.type.is(OptionalTypeSyntax.self)
            let defaultValue = param.defaultValue?.value.trimmedDescription
            return DiscoveredParameter(
                name: name,
                label: label,
                typeString: typeString,
                isOptional: isOptional,
                defaultValue: defaultValue
            )
        }
        let returnType = node.signature.returnClause?.type.trimmedDescription ?? "Void"
        let isAsync = node.signature.effectSpecifiers?.asyncSpecifier != nil
        let isThrowing = node.signature.effectSpecifiers?.throwsClause != nil

        // Extract description from doc comment if not explicitly given
        let docDescription = explicitDescription ?? extractDocDescription(from: node.leadingTrivia)

        tools.append(DiscoveredTool(
            extendedType: extendedType,
            functionName: funcName,
            wireName: customName ?? funcName,
            description: docDescription,
            parameters: parameters,
            returnTypeString: returnType,
            isAsync: isAsync,
            isThrowing: isThrowing
        ))

        return .visitChildren
    }
}

func extractDocDescription(from trivia: Trivia) -> String? {
    var lines: [String] = []
    for piece in trivia.pieces {
        switch piece {
        case .docLineComment(let text):
            var line = text
            if line.hasPrefix("///") { line.removeFirst(3) }
            line = line.trimmingCharacters(in: .whitespaces)
            // Stop collecting when we hit a parameter/return tag.
            if line.hasPrefix("- Parameter") || line.hasPrefix("- Returns") || line.hasPrefix("- Throws") {
                break
            }
            lines.append(line)
        case .docBlockComment(let text):
            // Strip /** */ and per-line *
            var stripped = text
            if stripped.hasPrefix("/**") { stripped.removeFirst(3) }
            if stripped.hasSuffix("*/") { stripped.removeLast(2) }
            for raw in stripped.split(separator: "\n") {
                var line = raw.trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("*") { line.removeFirst() }
                line = line.trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("- Parameter") || line.hasPrefix("- Returns") || line.hasPrefix("- Throws") {
                    return lines.isEmpty ? nil : lines.joined(separator: " ")
                }
                if !line.isEmpty { lines.append(line) }
            }
        default:
            break
        }
    }
    let joined = lines.joined(separator: " ").trimmingCharacters(in: .whitespaces)
    return joined.isEmpty ? nil : joined
}

// MARK: - Code generation

func swiftStringLiteral(_ s: String) -> String {
    var out = "\""
    for ch in s {
        switch ch {
        case "\\": out.append("\\\\")
        case "\"": out.append("\\\"")
        case "\n": out.append("\\n")
        case "\r": out.append("\\r")
        case "\t": out.append("\\t")
        default: out.append(ch)
        }
    }
    out.append("\"")
    return out
}

/// Best-effort schema type literal from a Swift type string.
/// The runtime `MCPParameterInfo` accepts `Any.Type`; we just need
/// enough type info to round-trip JSON arguments. Strips one level of
/// optional for the metadata's `type` field; `isRequired` carries the
/// optionality.
func schemaTypeExpr(for typeString: String) -> String {
    var t = typeString.trimmingCharacters(in: .whitespaces)
    if t.hasSuffix("?") { t.removeLast() }
    if t.hasPrefix("Optional<") && t.hasSuffix(">") {
        t.removeFirst("Optional<".count)
        t.removeLast()
    }
    return "\(t).self"
}

func generateBootstrap(moduleName: String, tools: [DiscoveredTool], imports: Set<String>) -> String {
    var out = ""
    out.append("// Generated by SwiftMCPAggregatorTool — DO NOT EDIT.\n")
    out.append("// Bootstrap for module \(moduleName).\n\n")

    var importsToEmit = imports
    importsToEmit.insert("SwiftMCP")
    importsToEmit.remove(moduleName)  // can't import self
    for imp in importsToEmit.sorted() {
        out.append("import \(imp)\n")
    }
    out.append("\n")

    out.append("public enum SwiftMCPBootstrap_\(sanitize(moduleName)) {\n")
    out.append("    public static func register() {\n")

    if tools.isEmpty {
        out.append("        // no @MCPExtensionTool declarations found\n")
    } else {
        let grouped = Dictionary(grouping: tools, by: \.extendedType)
        for (typeName, group) in grouped.sorted(by: { $0.key < $1.key }) {
            out.append("        \(typeName).__mcpRegisterExtensionTools([\n")
            for tool in group {
                out.append(emitEntry(tool: tool, server: typeName, indent: "            "))
            }
            out.append("        ])\n")
        }
    }

    out.append("    }\n")
    out.append("}\n")
    return out
}

func sanitize(_ s: String) -> String {
    var out = ""
    for ch in s {
        if ch.isLetter || ch.isNumber || ch == "_" {
            out.append(ch)
        } else {
            out.append("_")
        }
    }
    return out
}

func emitEntry(tool: DiscoveredTool, server: String, indent: String) -> String {
    var out = ""

    // --- MCPParameterInfo entries ---
    var paramExprs: [String] = []
    for p in tool.parameters {
        let isRequired = p.defaultValue == nil && !p.isOptional
        let defaultExpr: String = p.defaultValue.map { "\($0) as Sendable?" } ?? "nil"
        let pieces: [String] = [
            "name: \(swiftStringLiteral(p.name))",
            "type: \(schemaTypeExpr(for: p.typeString))",
            "description: nil",
            "defaultValue: \(defaultExpr)",
            "isRequired: \(isRequired)"
        ]
        paramExprs.append("MCPParameterInfo(\(pieces.joined(separator: ", ")))")
    }

    let paramList = paramExprs.isEmpty ? "[]" : "[\n\(indent)        " + paramExprs.joined(separator: ",\n\(indent)        ") + "\n\(indent)    ]"

    let descriptionExpr: String = tool.description.map(swiftStringLiteral) ?? "nil"
    let returnTypeExpr = schemaTypeExpr(for: tool.returnTypeString)

    out.append("\(indent)MCPExtensionToolEntry(\n")
    out.append("\(indent)    metadata: MCPToolMetadata(\n")
    out.append("\(indent)        name: \(swiftStringLiteral(tool.wireName)),\n")
    out.append("\(indent)        description: \(descriptionExpr),\n")
    out.append("\(indent)        parameters: \(paramList),\n")
    out.append("\(indent)        returnType: \(returnTypeExpr),\n")
    out.append("\(indent)        returnTypeDescription: nil,\n")
    out.append("\(indent)        isAsync: \(tool.isAsync),\n")
    out.append("\(indent)        isThrowing: \(tool.isThrowing),\n")
    out.append("\(indent)        isConsequential: true,\n")
    out.append("\(indent)        annotations: nil\n")
    out.append("\(indent)    ),\n")
    out.append("\(indent)    call: { server, args in\n")
    out.append("\(indent)        guard let s = server as? \(server) else {\n")
    out.append("\(indent)            throw MCPToolError.unknownTool(name: \(swiftStringLiteral(tool.wireName)))\n")
    out.append("\(indent)        }\n")

    // Argument extraction
    for p in tool.parameters {
        out.append("\(indent)        let \(p.name): \(p.typeString) = try args.extractValue(named: \(swiftStringLiteral(p.name)), as: \(p.typeString).self)\n")
    }

    // Build call expression
    let callArgs = tool.parameters.map { p -> String in
        if p.label == "_" { return p.name }
        if p.label == p.name { return "\(p.name): \(p.name)" }
        return "\(p.label): \(p.name)"
    }.joined(separator: ", ")

    let tryPrefix = tool.isThrowing ? "try " : ""
    let awaitPrefix = tool.isAsync ? "await " : ""

    if tool.returnTypeString == "Void" {
        out.append("\(indent)        \(tryPrefix)\(awaitPrefix)s.\(tool.functionName)(\(callArgs))\n")
        out.append("\(indent)        return \"\"\n")
    } else {
        out.append("\(indent)        return \(tryPrefix)\(awaitPrefix)s.\(tool.functionName)(\(callArgs))\n")
    }

    out.append("\(indent)    }\n")
    out.append("\(indent)),\n")

    return out
}

// MARK: - Driver

let args = parseArgs(CommandLine.arguments)
guard !args.moduleName.isEmpty, !args.outputPath.isEmpty else {
    FileHandle.standardError.write(Data("SwiftMCPAggregatorTool: --module and --output are required\n".utf8))
    exit(1)
}

let finder = ExtensionToolFinder(viewMode: .sourceAccurate)
for path in args.inputs {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
          let source = String(data: data, encoding: .utf8) else {
        continue
    }
    let tree = Parser.parse(source: source)
    finder.walk(tree)
}

let generated = generateBootstrap(moduleName: args.moduleName, tools: finder.tools, imports: finder.imports)

let outURL = URL(fileURLWithPath: args.outputPath)
try? FileManager.default.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
try generated.write(to: outURL, atomically: true, encoding: .utf8)
