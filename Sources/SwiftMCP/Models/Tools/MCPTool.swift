//
//  MCPTool.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 08.03.25.
//

import Foundation

/// Represents a tool that can be used by an AI model
public struct MCPTool: Sendable {
    /// The name of the tool
    public let name: String

    /// An optional description of the tool
    public let description: String?

    /// The JSON schema defining the tool's input parameters
    public let inputSchema: JSONSchema

    /// The JSON schema defining the tool's output, if available
    public let outputSchema: JSONSchema?

    /// Optional annotations providing hints about tool behavior (per MCP spec)
    public let annotations: MCPToolAnnotations?

    /// The `inputSchema` exactly as received, including keywords ``JSONSchema``
    /// cannot represent (SEP-2106). Set when decoding; takes precedence on encode.
    public let rawInputSchema: JSONValue?

    /// The `outputSchema` exactly as received (see ``rawInputSchema``).
    public let rawOutputSchema: JSONValue?

/**
	 Creates a new tool with the specified name, description, and input schema.

	 - Parameters:
	   - name: The name of the tool
	   - description: An optional description of the tool
	   - inputSchema: The schema defining the function's input parameters
       - outputSchema: The schema defining the function's output, if available
       - annotations: Optional hints about tool behavior
	 */
    public init(
        name: String,
        description: String? = nil,
        inputSchema: JSONSchema,
        outputSchema: JSONSchema? = nil,
        annotations: MCPToolAnnotations? = nil,
        rawInputSchema: JSONValue? = nil,
        rawOutputSchema: JSONValue? = nil
    ) {
        self.rawInputSchema = rawInputSchema
        self.rawOutputSchema = rawOutputSchema
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
        self.outputSchema = outputSchema
        self.annotations = annotations
    }
}

/**
 Extension to make MCPTool conform to Codable
 */
extension MCPTool: Codable {
    // MARK: - Codable Implementation

    private enum CodingKeys: String, CodingKey {
        case name
        case description
        case inputSchema
        case outputSchema
        case annotations
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decode(String.self, forKey: .name)
        let description = try container.decodeIfPresent(String.self, forKey: .description)
        // JSON Schema 2020-12 allows any keyword: keep the raw value for lossless
        // re-encoding and fall back to a permissive typed schema if the closed
        // `JSONSchema` model cannot represent it.
        let rawInput = try container.decode(JSONValue.self, forKey: .inputSchema)
        let rawOutput = try container.decodeIfPresent(JSONValue.self, forKey: .outputSchema)
        let inputSchema = (try? container.decode(JSONSchema.self, forKey: .inputSchema))
            ?? .object(JSONSchema.Object(properties: [:]))
        let outputSchema = rawOutput == nil ? nil : (try? container.decode(JSONSchema.self, forKey: .outputSchema))
            ?? .object(JSONSchema.Object(properties: [:]))
        let annotations = try container.decodeIfPresent(MCPToolAnnotations.self, forKey: .annotations)

        self.init(
            name: name,
            description: description,
            inputSchema: inputSchema,
            outputSchema: outputSchema,
            annotations: annotations,
            rawInputSchema: rawInput,
            rawOutputSchema: rawOutput
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(description, forKey: .description)
        if let rawInputSchema {
            try container.encode(rawInputSchema, forKey: .inputSchema)
        } else {
            try container.encode(inputSchema, forKey: .inputSchema)
        }
        if let rawOutputSchema {
            try container.encode(rawOutputSchema, forKey: .outputSchema)
        } else {
            try container.encodeIfPresent(outputSchema, forKey: .outputSchema)
        }
        try container.encodeIfPresent(annotations, forKey: .annotations)
    }
}

// MARK: - $ref resolution

public extension JSONValue {
    /// Returns a copy with local JSON Schema `$ref`s (`#/...` JSON Pointers, e.g.
    /// `#/$defs/Name`) replaced by their targets, resolved against `self` as the
    /// root schema. Sibling keywords of a `$ref` are kept (2020-12 semantics);
    /// unresolvable, remote and cyclic references are left untouched.
    func resolvingLocalRefs() -> JSONValue {
        resolveRefs(root: self, visiting: [])
    }

    private func resolveRefs(root: JSONValue, visiting: Set<String>) -> JSONValue {
        switch self {
        case .array(let items):
            return .array(items.map { $0.resolveRefs(root: root, visiting: visiting) })
        case .object(let dict):
            if let ref = dict["$ref"]?.stringValue, ref.hasPrefix("#"), !visiting.contains(ref),
               let target = root.pointer(String(ref.dropFirst())) {
                let resolvedTarget = target.resolveRefs(root: root, visiting: visiting.union([ref]))
                let siblings = dict.filter { $0.key != "$ref" }
                if siblings.isEmpty {
                    return resolvedTarget
                }
                // A boolean schema with siblings: `true` adds nothing, `false`
                // rejects everything, so keep it as an `allOf` member.
                guard var merged = resolvedTarget.dictionaryValue else {
                    var wrapped = siblings.mapValues { $0.resolveRefs(root: root, visiting: visiting) }
                    wrapped["allOf"] = .array([resolvedTarget])
                    return .object(wrapped)
                }
                for (key, value) in dict where key != "$ref" {
                    merged[key] = value.resolveRefs(root: root, visiting: visiting)
                }
                return .object(merged)
            }
            return .object(dict.mapValues { $0.resolveRefs(root: root, visiting: visiting) })
        default:
            return self
        }
    }

    /// Looks up an RFC 6901 JSON Pointer (`""` is the root).
    private func pointer(_ path: String) -> JSONValue? {
        // URI fragments are percent-encoded: decode before validating/splitting.
        let path = path.removingPercentEncoding ?? path
        if path.isEmpty { return self }
        guard path.hasPrefix("/") else { return nil }
        var current: JSONValue = self
        for rawToken in path.dropFirst().split(separator: "/", omittingEmptySubsequences: false) {
            let token = String(rawToken)
                .replacingOccurrences(of: "~1", with: "/")
                .replacingOccurrences(of: "~0", with: "~")
            switch current {
            case .object(let dict):
                guard let next = dict[token] else { return nil }
                current = next
            case .array(let items):
                guard let index = Int(token), items.indices.contains(index) else { return nil }
                current = items[index]
            default:
                return nil
            }
        }
        return current
    }
}
