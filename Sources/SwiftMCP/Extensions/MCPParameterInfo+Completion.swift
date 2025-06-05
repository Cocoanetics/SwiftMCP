import Foundation

public extension MCPParameterInfo {
    /// Provides default completion suggestions for this parameter.
    /// - Parameter prefix: The prefix already typed by the client.
    /// - Returns: Completion result based on the parameter's type.
    func defaultCompletion(prefix: String) -> CompleteResult.Completion {
        guard let caseType = type as? any CaseIterable.Type else {
            return CompleteResult.Completion(values: [])
        }

        let values = caseType.caseLabels.sortedByBestCompletion(prefix: prefix)
        return CompleteResult.Completion(values: values, total: values.count, hasMore: false)
    }

    /// Returns enum completions for this parameter if it is CaseIterable.
    /// - Parameter prefix: The prefix already typed by the client.
    /// - Returns: Completion result or nil if the parameter isn't an enum.
    func defaultEnumCompletion(prefix: String) -> CompleteResult.Completion? {
        guard type is any CaseIterable.Type else { return nil }
        return defaultCompletion(prefix: prefix)
    }
}
