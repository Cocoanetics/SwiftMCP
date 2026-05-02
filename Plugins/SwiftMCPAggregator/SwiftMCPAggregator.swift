//
//  SwiftMCPAggregator.swift
//
//  Build-tool plugin: scans the target's Swift source files and invokes
//  SwiftMCPAggregatorTool to produce a bootstrap file that registers
//  extension-defined tools at runtime.
//

import Foundation
import PackagePlugin

@main
struct SwiftMCPAggregator: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        guard let sourceTarget = target.sourceModule else { return [] }

        let inputs: [URL] = sourceTarget.sourceFiles(withSuffix: "swift").map(\.url)
        guard !inputs.isEmpty else { return [] }

        let outputDir = context.pluginWorkDirectoryURL
        let outputFile = outputDir.appending(path: "SwiftMCPBootstrap_\(sanitize(target.name)).swift")

        let tool = try context.tool(named: "SwiftMCPAggregatorTool")

        var arguments: [String] = [
            "--module", target.name,
            "--output", outputFile.path
        ]
        arguments.append(contentsOf: inputs.map(\.path))

        return [
            .buildCommand(
                displayName: "Aggregating MCP extension tools for \(target.name)",
                executable: tool.url,
                arguments: arguments,
                inputFiles: inputs,
                outputFiles: [outputFile]
            )
        ]
    }

    private func sanitize(_ s: String) -> String {
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
}
