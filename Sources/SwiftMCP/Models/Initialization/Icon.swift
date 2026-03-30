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
    
    public enum Size: Sendable {
        case pixels(width: Int, height: Int)
        case any
    }
    
    public var src: URL
    
    public var mimeType: String?
    
    public var sizes: [String]?
    
    public var theme: Theme?
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
