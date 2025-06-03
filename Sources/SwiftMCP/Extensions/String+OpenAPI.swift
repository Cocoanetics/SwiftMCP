import Foundation

extension String {
/// Formats a string to be used as a model name:
/// - Converts to lowercase
/// - Splits on non-alphanumeric characters
/// - Joins with underscores
    var asModelName: String {
        self.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "_")
    }
} 
