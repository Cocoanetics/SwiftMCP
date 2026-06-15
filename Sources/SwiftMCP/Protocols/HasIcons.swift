//
//  HasIcons.swift
//  SwiftMCP
//
//  Opt-in capability for advertising display icons in `serverInfo`.
//

import Foundation

/// Conform an `@MCPServer` type to `HasIcons` to advertise display icons in its
/// `serverInfo`.
///
/// Icons are part of the server identity from protocol version `2025-06-18`.
/// Most servers have none, so this is an explicit opt-in rather than a member of
/// the base ``MCPServer`` surface — a conforming server simply returns its icons:
///
/// ```swift
/// @MCPServer(name: "weather", title: "Weather Tools")
/// final class WeatherServer: HasIcons {
///     var icons: [Icon] { [Icon("https://example.com/icon.png", mimeType: "image/png")] }
/// }
/// ```
public protocol HasIcons {
    /// The display icons for this server. An empty array means none.
    var icons: [Icon] { get }
}
