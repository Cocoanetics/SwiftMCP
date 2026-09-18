import Foundation
import Testing
@testable import SwiftMCP

@Suite("Server capabilities decoding")
struct LoggingCapabilityDecodingTests {

    /// The MCP spec declares the logging capability as an empty object, so its
    /// presence is the signal. Requiring `enabled` made initialize fail against
    /// any compliant server advertising `"logging": {}`.
    @Test("logging: {} decodes as enabled")
    func emptyLoggingObjectDecodes() throws {
        let json = #"{"logging":{},"tools":{}}"#.data(using: .utf8)!
        let caps = try JSONDecoder().decode(ServerCapabilities.self, from: json)
        #expect(caps.logging != nil)
        #expect(caps.logging?.enabled == true)
    }

    @Test("an explicit enabled flag is still honoured")
    func explicitFlagHonoured() throws {
        let json = #"{"logging":{"enabled":false}}"#.data(using: .utf8)!
        let caps = try JSONDecoder().decode(ServerCapabilities.self, from: json)
        #expect(caps.logging?.enabled == false)
    }

    @Test("absent logging stays nil")
    func absentLoggingIsNil() throws {
        let json = #"{"tools":{"listChanged":true}}"#.data(using: .utf8)!
        let caps = try JSONDecoder().decode(ServerCapabilities.self, from: json)
        #expect(caps.logging == nil)
        #expect(caps.tools?.listChanged == true)
    }
}
