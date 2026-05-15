//
//  SwiftMCPAggregatorTool — main.swift
//
//  Scans target sources for `@MCPExtension(...)` extensions and emits one
//  `extension <ServerType>.Client { ... }` per extended type, aggregating
//  every `@MCPTool`/`@MCPResource`/`@MCPPrompt` from every contributing
//  extension in the target into a single Client extension. The methods
//  mirror what `@MCPServer(generateClient: true)` emits for the primary
//  type's tools/resources/prompts.
//
//  Macro infrastructure does not allow `@MCPExtension` to emit
//  `extension <Type>.Client` from any role attached to an extension
//  declaration. The build plugin runs at file-emission level, where that
//  restriction does not apply.
//
//  CLI:
//    SwiftMCPAggregatorTool --module <Name> --output <path> [<input.swift> ...]
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
    var index = 1
    while index < argv.count {
        let arg = argv[index]
        switch arg {
        case "--module":
            index += 1
            moduleName = argv[index]
        case "--output":
            index += 1
            outputPath = argv[index]
        default:
            inputs.append(arg)
        }
        index += 1
    }
    return ToolArgs(moduleName: moduleName, outputPath: outputPath, inputs: inputs)
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

let generated = generateOutput(moduleName: args.moduleName, byType: finder.byExtendedType, imports: finder.imports)
let outURL = URL(fileURLWithPath: args.outputPath)
try? FileManager.default.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
try generated.write(to: outURL, atomically: true, encoding: .utf8)
