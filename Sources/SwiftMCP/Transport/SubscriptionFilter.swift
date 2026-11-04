import Foundation

/// The notification types a client opts in to on a modern `subscriptions/listen`
/// request (`SubscriptionFilter` in the draft schema). Each type is opt-in; the
/// server never sends one the client did not request. The same shape is echoed in
/// `notifications/subscriptions/acknowledged`, narrowed to what the server honors.
struct SubscriptionFilter: Sendable, Equatable {
    var toolsListChanged = false
    var promptsListChanged = false
    var resourcesListChanged = false
    var resourceSubscriptions: Set<String> = []

    /// Parses the `notifications` object of a `subscriptions/listen` request.
    /// Returns `nil` when a field has the wrong type; unknown fields are ignored.
    init?(_ value: JSONValue?) {
        guard let dictionary = value?.dictionaryValue,
              let tools = Self.flag(dictionary["toolsListChanged"]),
              let prompts = Self.flag(dictionary["promptsListChanged"]),
              let resources = Self.flag(dictionary["resourcesListChanged"]) else {
            return nil
        }
        toolsListChanged = tools
        promptsListChanged = prompts
        resourcesListChanged = resources

        if let field = dictionary["resourceSubscriptions"] {
            guard let items = field.arrayValue else {
                return nil
            }
            let uris = items.compactMap(\.stringValue)
            guard uris.count == items.count else {
                return nil
            }
            resourceSubscriptions = Set(uris)
        }
    }

    /// An absent flag is `false`; a present one must be a boolean (`nil` otherwise).
    private static func flag(_ value: JSONValue?) -> Bool? {
        guard let value else {
            return false
        }
        return value.boolValue
    }

    /// The filter narrowed to the notification types the server can produce;
    /// nothing is honored when the capabilities are unknown.
    func honored(by capabilities: ServerCapabilities?) -> SubscriptionFilter {
        guard let capabilities else {
            return SubscriptionFilter(.object([:])) ?? self
        }
        var result = self
        result.toolsListChanged = toolsListChanged && capabilities.tools != nil
        result.promptsListChanged = promptsListChanged && capabilities.prompts != nil
        result.resourcesListChanged = resourcesListChanged && capabilities.resources != nil
        if capabilities.resources?.subscribe != true {
            result.resourceSubscriptions = []
        }
        return result
    }

    /// Whether the filter asks for no notifications at all.
    var isEmpty: Bool {
        !toolsListChanged && !promptsListChanged && !resourcesListChanged && resourceSubscriptions.isEmpty
    }

    /// The wire form: only requested types appear.
    var jsonValue: JSONValue {
        var object: JSONDictionary = [:]
        if toolsListChanged { object["toolsListChanged"] = .bool(true) }
        if promptsListChanged { object["promptsListChanged"] = .bool(true) }
        if resourcesListChanged { object["resourcesListChanged"] = .bool(true) }
        if !resourceSubscriptions.isEmpty {
            object["resourceSubscriptions"] = .array(resourceSubscriptions.sorted().map { .string($0) })
        }
        return .object(object)
    }
}
