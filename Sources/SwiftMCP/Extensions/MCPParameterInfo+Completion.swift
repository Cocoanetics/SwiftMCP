import Foundation

public extension MCPParameterInfo {
    /// Provides default completion suggestions for this parameter.
    /// - Returns: Completion result based on the parameter's type.
    var defaultCompletions: [String] {
        
        if type is Bool.Type
        {
            return ["true", "false"]
        }
        
        guard let caseType = type as? any CaseIterable.Type else {
            return []
        }

        return caseType.caseLabels
    }
}
