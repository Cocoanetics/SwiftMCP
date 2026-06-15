//
//  Implementation.swift
//  SwiftMCP
//
//  Created by Pawel Gil on 07/03/2026.
//

import Foundation

public struct Implementation: Codable, Sendable {
    public var icons: [Icon]?

    public var name: String

    public var title: String?

    public var version: String

    public var description: String?

    public var websiteUrl: URL?

    // Parameter order mirrors the synthesized memberwise initializer so existing
    // call sites keep compiling; `name`/`version` are required, the rest optional.
    public init(
        icons: [Icon]? = nil,
        name: String,
        title: String? = nil,
        version: String,
        description: String? = nil,
        websiteUrl: URL? = nil
    ) {
        self.icons = icons
        self.name = name
        self.title = title
        self.version = version
        self.description = description
        self.websiteUrl = websiteUrl
    }
}
