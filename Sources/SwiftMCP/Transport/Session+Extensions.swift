import Foundation
import NIO

extension Session {
    /// Send a progress notification to the client associated with this session.
    /// - Parameters:
    ///   - progressToken: The token identifying the operation progress belongs to.
    ///   - progress: Current progress value.
    ///   - total: Optional total value if known.
    ///   - message: Optional human-readable progress message.
    public func sendProgressNotification(progressToken: JSONValue,
                                         progress: Double,
                                         total: Double? = nil,
                                         message: String? = nil) async {
        var params: JSONDictionary = [
            "progressToken": progressToken,
            "progress": .double(progress)
        ]
        if let total = total { params["total"] = .double(total) }
        if let message = message { params["message"] = .string(message) }

        let notification = JSONRPCMessage.notification(method: "notifications/progress",
                                                       params: params)
        try? await transport?.send(notification)
    }

    /// Send a log message notification to the client associated with this session, filtered by minimumLogLevel.
    /// - Parameter message: The log message to send
    public func sendLogNotification(_ message: LogMessage) async {
        guard message.level.isAtLeast(self.minimumLogLevel) else { return }
        var params: JSONDictionary = [
            "level": .string(message.level.rawValue),
            "data": message.data
        ]
        if let logger = message.logger { params["logger"] = .string(logger) }

        let notification = JSONRPCMessage.notification(method: "notifications/message",
                                                       params: params)
        try? await transport?.send(notification)
    }

    /// Send a roots/list request to the client and return the roots.
    /// - Returns: The list of roots available to the client
    /// - Throws: An error if the request fails
    public func listRoots() async throws -> [Root] {
        // Check if client supports roots
        guard clientCapabilities?.roots != nil else {
            // Return empty array when client doesn't support roots
            return []
        }
        
        let response = try await request(method: "roots/list", params: [:])
        
        // Parse the response to extract the roots list
        guard case .response(let responseData) = response else {
            throw MCPServerError.unexpectedMessageType(method: "roots/list")
        }
        
        guard let result = responseData.result,
              let rootsValue = result["roots"] else {
            preconditionFailure("Malformed roots response")
        }

        return try rootsValue.decoded([Root].self)
    }

    /// Send a notification that the list of available tools changed.
    public func sendToolListChanged() async throws {
        let notification = JSONRPCMessage.notification(method: "notifications/tools/list_changed")
        try await transport?.send(notification)
    }

    /// Send a notification that the list of available resources changed.
    public func sendResourceListChanged() async throws {
        let notification = JSONRPCMessage.notification(method: "notifications/resources/list_changed")
        try await transport?.send(notification)
    }

    /// Send a notification that the list of available prompts changed.
    public func sendPromptListChanged() async throws {
        let notification = JSONRPCMessage.notification(method: "notifications/prompts/list_changed")
        try await transport?.send(notification)
    }

    /// Subscribe this session to resource-updated notifications for a URI.
    public func subscribeResource(uri: String) {
        subscribedResourceURIs.insert(uri)
    }

    /// Unsubscribe this session from resource-updated notifications for a URI.
    public func unsubscribeResource(uri: String) {
        subscribedResourceURIs.remove(uri)
    }

    /// Returns `true` if this session is subscribed to updates for the given URI.
    public func isSubscribedToResource(uri: String) -> Bool {
        subscribedResourceURIs.contains(uri)
    }

    /// Send a notification that a subscribed resource has been updated.
    /// - Parameter uri: The URI of the resource that was updated.
    public func sendResourceUpdated(uri: URL) async throws {
        let notification = JSONRPCMessage.notification(
            method: "notifications/resources/updated",
            params: ["uri": .string(uri.absoluteString)]
        )
        try await transport?.send(notification)
    }
}
