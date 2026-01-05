import Foundation

/// Optional annotations for tool content and resources.
public struct MCPContentAnnotations: Codable, Sendable {
    public let audience: [String]?
    public let priority: Double?
    public let lastModified: Date?

    public init(audience: [String]? = nil, priority: Double? = nil, lastModified: Date? = nil) {
        self.audience = audience
        self.priority = priority
        self.lastModified = lastModified
    }
}

/// Text content returned by a tool.
public struct MCPText: Codable, Sendable {
    public let text: String

    public init(_ text: String) {
        self.text = text
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case text
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        _ = try container.decodeIfPresent(String.self, forKey: .type)
        text = try container.decode(String.self, forKey: .text)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("text", forKey: .type)
        try container.encode(text, forKey: .text)
    }
}

/// Image content returned by a tool.
public struct MCPImage: Codable, Sendable {
    public let data: Data
    public let mimeType: String
    public let annotations: MCPContentAnnotations?

    public init(data: Data, mimeType: String, annotations: MCPContentAnnotations? = nil) {
        self.data = data
        self.mimeType = mimeType
        self.annotations = annotations
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case data
        case mimeType
        case annotations
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        _ = try container.decodeIfPresent(String.self, forKey: .type)
        data = try container.decode(Data.self, forKey: .data)
        mimeType = try container.decode(String.self, forKey: .mimeType)
        annotations = try container.decodeIfPresent(MCPContentAnnotations.self, forKey: .annotations)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("image", forKey: .type)
        try container.encode(data, forKey: .data)
        try container.encode(mimeType, forKey: .mimeType)
        try container.encodeIfPresent(annotations, forKey: .annotations)
    }
}

/// Audio content returned by a tool.
public struct MCPAudio: Codable, Sendable {
    public let data: Data
    public let mimeType: String
    public let annotations: MCPContentAnnotations?

    public init(data: Data, mimeType: String, annotations: MCPContentAnnotations? = nil) {
        self.data = data
        self.mimeType = mimeType
        self.annotations = annotations
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case data
        case mimeType
        case annotations
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        _ = try container.decodeIfPresent(String.self, forKey: .type)
        data = try container.decode(Data.self, forKey: .data)
        mimeType = try container.decode(String.self, forKey: .mimeType)
        annotations = try container.decodeIfPresent(MCPContentAnnotations.self, forKey: .annotations)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("audio", forKey: .type)
        try container.encode(data, forKey: .data)
        try container.encode(mimeType, forKey: .mimeType)
        try container.encodeIfPresent(annotations, forKey: .annotations)
    }
}

/// A tool-returned link to a resource.
public struct MCPResourceLink: Codable, Sendable {
    public let uri: URL
    public let name: String
    public let description: String?
    public let mimeType: String?
    public let annotations: MCPContentAnnotations?

    public init(
        uri: URL,
        name: String,
        description: String? = nil,
        mimeType: String? = nil,
        annotations: MCPContentAnnotations? = nil
    ) {
        self.uri = uri
        self.name = name
        self.description = description
        self.mimeType = mimeType
        self.annotations = annotations
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case uri
        case name
        case description
        case mimeType
        case annotations
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        _ = try container.decodeIfPresent(String.self, forKey: .type)
        uri = try container.decode(URL.self, forKey: .uri)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType)
        annotations = try container.decodeIfPresent(MCPContentAnnotations.self, forKey: .annotations)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("resource_link", forKey: .type)
        try container.encode(uri, forKey: .uri)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(mimeType, forKey: .mimeType)
        try container.encodeIfPresent(annotations, forKey: .annotations)
    }
}

/// Embedded resource content returned by a tool.
public struct MCPEmbeddedResource: Codable, Sendable {
    public struct Resource: Codable, Sendable {
        public let uri: URL
        public let mimeType: String?
        public let text: String?
        public let blob: Data?
        public let annotations: MCPContentAnnotations?

        public init(
            uri: URL,
            mimeType: String? = nil,
            text: String? = nil,
            blob: Data? = nil,
            annotations: MCPContentAnnotations? = nil
        ) {
            self.uri = uri
            self.mimeType = mimeType
            self.text = text
            self.blob = blob
            self.annotations = annotations
        }
    }

    public let resource: Resource

    public init(resource: Resource) {
        self.resource = resource
    }

    public init(resource: MCPResourceContent, annotations: MCPContentAnnotations? = nil) {
        self.resource = Resource(
            uri: resource.uri,
            mimeType: resource.mimeType,
            text: resource.text,
            blob: resource.blob,
            annotations: annotations
        )
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case resource
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        _ = try container.decodeIfPresent(String.self, forKey: .type)
        resource = try container.decode(Resource.self, forKey: .resource)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("resource", forKey: .type)
        try container.encode(resource, forKey: .resource)
    }
}
