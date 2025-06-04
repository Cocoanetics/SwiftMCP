import Foundation

/// Represents the completion results returned by the server.
public struct CompleteResult: Codable, Sendable {
    /// The completion information containing the suggested values.
    public struct Completion: Codable, Sendable {
        public let values: [String]
        public let total: Int?
        public let hasMore: Bool?

        public init(values: [String], total: Int? = nil, hasMore: Bool? = nil) {
            self.values = values
            self.total = total
            self.hasMore = hasMore
        }
    }

    public let completion: Completion

    public init(values: [String], total: Int? = nil, hasMore: Bool? = nil) {
        self.completion = Completion(values: values, total: total, hasMore: hasMore)
    }
}
