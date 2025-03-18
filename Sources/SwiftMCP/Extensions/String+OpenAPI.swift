import Foundation

 extension String {
    /// Formats a string to be used as a model name:
    /// - Converts to lowercase
    /// - Replaces spaces with underscores
    /// - Removes any characters that aren't alphanumeric or underscores
    var asModelName: String {
        self.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "[^a-z0-9_]", with: "", options: .regularExpression)
    }
} 
