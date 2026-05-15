import Foundation

// MARK: - Logging
public extension MCPServer {
    /**
     Handles a logging level configuration request.

     - Parameter request: The JSON-RPC request containing the logging level details
     - Returns: A JSON-RPC message containing the result
     */
    internal func handleLoggingSetLevel(
        _ request: JSONRPCMessage.JSONRPCRequestData
    ) async -> JSONRPCMessage? {
        guard let session = Session.current else {
            return JSONRPCMessage.errorResponse(
                id: request.id,
                error: .init(code: -32603, message: "No session context for logging/setLevel")
            )
        }

        guard let params = request.params,
              let levelString = params["level"]?.stringValue else {
            return JSONRPCMessage.errorResponse(
                id: request.id,
                error: .init(code: -32602, message: "Invalid parameters: 'level' parameter is required")
            )
        }

        guard let level = LogLevel(string: levelString) else {
            let validLevels = LogLevel.allCases.map(\.rawValue).joined(separator: ", ")
            return JSONRPCMessage.errorResponse(
                id: request.id,
                error: .init(
                    code: -32602,
                    message: "Invalid log level: '\(levelString)'. Valid levels are: \(validLevels)"
                )
            )
        }

        // Set the minimum log level for this session
        await session.setMinimumLogLevel(level)

        // Return empty result for success
        return JSONRPCMessage.response(id: request.id, result: [:])
    }
}
