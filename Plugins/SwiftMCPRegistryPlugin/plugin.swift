import Foundation
import PackagePlugin

@main
struct SwiftMCPRegistryPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        guard let sourceTarget = target as? SourceModuleTarget else {
            return []
        }

        let tool = try context.tool(named: "SwiftMCPRegistryTool")
        let outputFile = context.pluginWorkDirectory.appending("MCPGeneratedRegistry_\(sourceTarget.name).swift")
        let sourceFiles = sourceTarget.sourceFiles(withSuffix: "swift")

        return [
            .buildCommand(
                displayName: "Generate SwiftMCP registry for \(sourceTarget.name)",
                executable: tool.path,
                arguments: [sourceTarget.name, outputFile.string] + sourceFiles.map { $0.path.string },
                inputFiles: sourceFiles.map { $0.path },
                outputFiles: [outputFile]
            )
        ]
    }
}
