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
}

