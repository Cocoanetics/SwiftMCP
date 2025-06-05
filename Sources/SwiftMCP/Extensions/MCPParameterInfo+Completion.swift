import Foundation

public extension MCPParameterInfo {
    /// Provides default completion suggestions for this parameter.
    /// - Returns: Completion result based on the parameter's type.
    var defaultCompletions: [String] {
        guard let caseType = type as? any CaseIterable.Type else {
            return []
        }

        return caseType.caseLabels
    }
}
