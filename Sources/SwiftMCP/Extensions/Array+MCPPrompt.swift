import Foundation

extension Array where Element == MCPPromptMetadata {
    /// Converts an array of prompt metadata to user-facing `Prompt` objects
    public func convertedToPrompts() -> [Prompt] {
        self.map { meta in
            Prompt(name: meta.name, description: meta.description, arguments: meta.parameters)
        }
    }
}
