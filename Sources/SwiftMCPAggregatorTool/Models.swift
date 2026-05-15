//
//  Models.swift
//  SwiftMCPAggregatorTool
//
//  Value types describing the contributions discovered while scanning
//  target sources for `@MCPExtension` extensions.
//

import Foundation

enum ContributionKind {
    case tool(wireName: String)
    case resource(templates: [String])
    case prompt
}

struct DiscoveredParameter {
    var name: String
    var label: String
    var typeString: String
    var defaultValue: String?
    var isOptional: Bool
}

struct DiscoveredMethod {
    var kind: ContributionKind
    var functionName: String
    var parameters: [DiscoveredParameter]
    var returnTypeString: String?
    var isAsync: Bool
    var isThrowing: Bool
    var throwsKeyword: String?
    var docComment: String?
    var paramDocs: [String: String]
    var returnsDoc: String?
    /// Joined `#if` condition covering the method's source location, or
    /// empty if the method is not inside any `#if` block.
    var ifConfigCondition: String
}

struct ParsedDocComment {
    let description: String?
    let params: [String: String]
    let returns: String?
}
