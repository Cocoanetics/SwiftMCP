import Foundation

extension Array where Element == String {
    /// Returns the array sorted so that strings with the longest prefix match
    /// come first. The comparison is case-insensitive.
    /// - Parameter prefix: The prefix typed by the client.
    func sortedByBestCompletion(prefix: String) -> [String] {
        let lower = prefix.lowercased()
        return self.enumerated().sorted { lhs, rhs in
            let lMatch = lhs.element.lowercased().commonPrefix(with: lower).count
            let rMatch = rhs.element.lowercased().commonPrefix(with: lower).count
            if lMatch == rMatch {
                return lhs.offset < rhs.offset
            }
            return lMatch > rMatch
        }.map { $0.element }
    }
}
