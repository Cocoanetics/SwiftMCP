//
//  Icon.swift
//  SwiftMCP
//
//  Created by Pawel Gil on 07/03/2026.
//

import Foundation

public struct Icon: Codable, Sendable {
    public enum Theme: String, Codable, Sendable {
        case light
        case dark
    }

    public enum Size: Sendable, Equatable {
        case pixels(width: Int, height: Int)
        case any
    }

    public var src: URL

    public var mimeType: String?

    public var sizes: [Size]?

    public var theme: Theme?

    public init(src: URL, mimeType: String? = nil, sizes: [Size]? = nil, theme: Theme? = nil) {
        self.src = src
        self.mimeType = mimeType
        self.sizes = sizes
        self.theme = theme
    }

    /// Convenience initializer from a string URL. Traps on a malformed URL —
    /// intended for compile-time-constant icon URLs.
    public init(_ src: String, mimeType: String? = nil, sizes: [Size]? = nil, theme: Theme? = nil) {
        guard let url = URL(string: src) else {
            preconditionFailure("Invalid icon URL: \(src)")
        }
        self.init(src: url, mimeType: mimeType, sizes: sizes, theme: theme)
    }
}

extension Icon.Size: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        if string == "any" {
            self = .any
        } else {
            let parts = string.split(separator: "x")
            guard parts.count == 2,
                  let width = Int(parts[0]),
                  let height = Int(parts[1]) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Expected format \"WxH\" or \"any\", got \"\(string)\""
                )
            }
            self = .pixels(width: width, height: height)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .pixels(let width, let height):
            try container.encode("\(width)x\(height)")
        case .any:
            try container.encode("any")
        }
    }
}
