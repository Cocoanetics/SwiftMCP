import Foundation

/// Represents a completion request referencing a prompt or resource.
public struct CompleteRequest: Codable, Sendable {
    /// Identifies the argument being completed.
    public struct Argument: Codable, Sendable {
        public let name: String
        public let value: String?

        public init(name: String, value: String? = nil) {
            self.name = name
            self.value = value
        }
    }

    /// Reference to the prompt or resource context for the completion.
    public enum Reference: Codable, Sendable {
        case prompt(name: String)
        case resource(uri: String)

        private enum CodingKeys: String, CodingKey { case type, name, uri }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)
            switch type {
            case "ref/prompt":
                let name = try container.decode(String.self, forKey: .name)
                self = .prompt(name: name)
            case "ref/resource":
                let uri = try container.decode(String.self, forKey: .uri)
                self = .resource(uri: uri)
            default:
                throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown reference type")
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .prompt(let name):
                try container.encode("ref/prompt", forKey: .type)
                try container.encode(name, forKey: .name)
            case .resource(let uri):
                try container.encode("ref/resource", forKey: .type)
                try container.encode(uri, forKey: .uri)
            }
        }
    }

    public let ref: Reference
    public let argument: Argument

    public init(ref: Reference, argument: Argument) {
        self.ref = ref
        self.argument = argument
    }
}
