//
//  MCPAppShortcutsProvider.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 19.03.25.
//

#if canImport(AppIntents)
import AppIntents

/// Typealias used by macros to avoid requiring AppIntents imports at expansion sites.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
public typealias MCPAppShortcutsProvider = AppShortcutsProvider
#else
/// Stub protocol for platforms without AppIntents support.
public protocol MCPAppShortcutsProvider {}
#endif
