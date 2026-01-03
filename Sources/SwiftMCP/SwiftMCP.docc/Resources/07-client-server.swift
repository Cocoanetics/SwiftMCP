import SwiftMCP

@MCPServer(generateClient: true)
actor CalculatorServer {
    /// Adds two integers.
    /// - Parameter a: First value.
    /// - Parameter b: Second value.
    /// - Returns: The sum.
    @MCPTool
    func add(a: Int, b: Int) -> Int {
        a + b
    }

    /// Formats a date as ISO 8601.
    /// - Parameter date: The date to format.
    /// - Returns: A formatted string.
    @MCPTool
    func format(date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
