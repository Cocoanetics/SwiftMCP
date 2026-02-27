import PackagePlugin

@main
struct SwiftMCPAggregatorPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        guard let sourceTarget = target as? SourceModuleTarget else {
            return []
        }

        let tool = try context.tool(named: "SwiftMCPAggregatorTool")
        let outputFile = context.pluginWorkDirectory.appending("MCPGeneratedBootstrap_\(sourceTarget.name).swift")

        var moduleNames: [String] = []
        for dependency in sourceTarget.dependencies {
            switch dependency {
            case .target(let target):
                moduleNames.append(target.name)
            default:
                break
            }
        }

        let uniqueModules = Array(Set(moduleNames)).sorted()

        return [
            .buildCommand(
                displayName: "Generate SwiftMCP bootstrap for \(sourceTarget.name)",
                executable: tool.path,
                arguments: [outputFile.string] + uniqueModules,
                inputFiles: [],
                outputFiles: [outputFile]
            )
        ]
    }
}
