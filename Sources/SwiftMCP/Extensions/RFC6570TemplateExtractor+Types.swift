import Foundation

// MARK: - Supporting Types

/// RFC 6570 expression operator prefix.
internal enum ExpressionOperator {
    case simple             // {var}
    case reserved           // {+var}
    case fragment           // {#var}
    case label              // {.var}
    case pathSegment        // {/var}
    case pathStyle          // {;var}
    case query              // {?var}
    case queryContinuation  // {&var}
}

/// Parsed variable specification from a template expression.
internal struct VariableSpec {
    let name: String
    let modifier: VariableModifier
}

/// Modifier applied to a variable spec (prefix or explode).
internal enum VariableModifier {
    case none
    case prefix(Int)
    case explode
}

extension RFC6570TemplateExtractor {
    /// Result of extracting a single variable from a URL slice.
    struct ExtractedVariable {
        let variableName: String
        let value: String
        let consumedLength: Int
    }
}
