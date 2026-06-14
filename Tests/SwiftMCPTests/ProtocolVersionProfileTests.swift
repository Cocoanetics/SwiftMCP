import Foundation
import Testing
@testable import SwiftMCP

@Suite("Protocol Version Profile")
struct ProtocolVersionProfileTests {

    // MARK: - Golden matrix

    /// The exact, expected feature set for each known revision, written as flat
    /// literals so this is an *independent* source of truth from the
    /// `deriving(...)` chain in the implementation. Any accidental drift in a
    /// profile shows up as a diff here.
    static let goldenMatrix: [String: Set<MCPFeature>] = [
        "2024-11-05": [
            .initializeHandshake, .protocolLevelSessions, .standaloneGetStream,
            .serverInitiatedRequests, .subscribeUnsubscribe,
            .ping, .loggingSetLevel, .rootsListChangedNotification
        ],
        "2025-03-26": [
            .initializeHandshake, .protocolLevelSessions, .standaloneGetStream,
            .serverInitiatedRequests, .subscribeUnsubscribe,
            .ping, .loggingSetLevel, .rootsListChangedNotification,
            .jsonRPCBatching, .resumableStreams,
            .toolAnnotations, .audioContent, .completionsCapability
        ],
        "2025-06-18": [
            .initializeHandshake, .protocolLevelSessions, .standaloneGetStream,
            .serverInitiatedRequests, .subscribeUnsubscribe,
            .ping, .loggingSetLevel, .rootsListChangedNotification,
            .resumableStreams, .toolAnnotations, .audioContent, .completionsCapability,
            .protocolVersionHeader, .elicitation, .structuredToolOutput,
            .resourceLinks, .titleField
        ],
        "2025-11-25": [
            .initializeHandshake, .protocolLevelSessions, .standaloneGetStream,
            .serverInitiatedRequests, .subscribeUnsubscribe,
            .ping, .loggingSetLevel, .rootsListChangedNotification,
            .resumableStreams, .toolAnnotations, .audioContent, .completionsCapability,
            .protocolVersionHeader, .elicitation, .structuredToolOutput,
            .resourceLinks, .titleField
        ],
        "2026-07-28": [
            .perRequestMetadata, .serverDiscover, .standardRequestHeaders,
            .xMcpHeader, .protocolVersionHeader,
            .mrtr, .subscriptionsListen,
            .elicitation, .structuredToolOutput, .resourceLinks,
            .toolAnnotations, .audioContent, .completionsCapability, .titleField,
            .perRequestLogLevel, .cacheableListResults
        ]
    ]

    @Test("Every known profile matches the golden matrix")
    func goldenMatrixMatches() throws {
        for profile in MCPProtocolVersion.allKnownProfiles {
            let expected = try #require(
                Self.goldenMatrix[profile.version],
                "No golden entry for \(profile.version)"
            )
            #expect(
                profile.features == expected,
                "\(profile.version): unexpected \(profile.features.symmetricDifference(expected))"
            )
        }
    }

    @Test("Golden matrix and allKnownProfiles cover the same versions")
    func sameVersionsCovered() {
        let known = Set(MCPProtocolVersion.allKnownProfiles.map(\.version))
        #expect(known == Set(Self.goldenMatrix.keys))
    }

    // MARK: - Lookup

    @Test("profile(for:) returns the matching profile")
    func lookupHits() {
        #expect(MCPProtocolVersion.profile(for: "2025-11-25")?.era == .legacy)
        #expect(MCPProtocolVersion.profile(for: "2026-07-28")?.era == .modern)
    }

    @Test("profile(for:) returns nil for an unknown version")
    func lookupMisses() {
        #expect(MCPProtocolVersion.profile(for: "1900-01-01") == nil)
        #expect(MCPProtocolVersion.profile(for: "") == nil)
    }

    @Test("Every negotiable version has a profile")
    func supportedVersionsHaveProfiles() {
        for version in MCPProtocolVersion.supported {
            #expect(MCPProtocolVersion.profile(for: version) != nil, "missing profile for \(version)")
        }
    }

    @Test("modern is described but not yet negotiable")
    func modernNotYetSupported() {
        #expect(MCPProtocolVersion.profile(for: MCPProtocolVersion.modern) != nil)
        #expect(!MCPProtocolVersion.supported.contains(MCPProtocolVersion.modern))
    }

    // MARK: - The batching delta (the motivating case)

    @Test("JSON-RPC batching is only on for the revisions that defined it")
    func batchingMatrix() {
        #expect(MCPProtocolVersion.profile(for: "2024-11-05")?.has(.jsonRPCBatching) == false)
        #expect(MCPProtocolVersion.profile(for: "2025-03-26")?.has(.jsonRPCBatching) == true)
        #expect(MCPProtocolVersion.profile(for: "2025-06-18")?.has(.jsonRPCBatching) == false)
        #expect(MCPProtocolVersion.profile(for: "2025-11-25")?.has(.jsonRPCBatching) == false)
        #expect(MCPProtocolVersion.profile(for: "2026-07-28")?.has(.jsonRPCBatching) == false)
    }

    // MARK: - Era invariants

    @Test("Legacy revisions handshake and hold sessions; modern does neither")
    func eraInvariants() {
        let legacy = ["2024-11-05", "2025-03-26", "2025-06-18", "2025-11-25"]
        for version in legacy {
            let profile = MCPProtocolVersion.profile(for: version)
            #expect(profile?.era == .legacy)
            #expect(profile?.has(.initializeHandshake) == true)
            #expect(profile?.has(.protocolLevelSessions) == true)
            #expect(profile?.has(.serverInitiatedRequests) == true)
            #expect(profile?.has(.mrtr) == false)
        }

        let modern = MCPProtocolVersion.profile(for: "2026-07-28")
        #expect(modern?.isModern == true)
        #expect(modern?.has(.initializeHandshake) == false)
        #expect(modern?.has(.protocolLevelSessions) == false)
        #expect(modern?.has(.ping) == false)
        #expect(modern?.has(.loggingSetLevel) == false)
        #expect(modern?.has(.mrtr) == true)
        #expect(modern?.has(.serverInitiatedRequests) == false)
    }

    // MARK: - Derived value facets

    @Test("Resource-not-found code follows the era")
    func resourceNotFoundCode() {
        #expect(MCPProtocolVersion.profile(for: "2025-11-25")?.resourceNotFoundCode == -32001)
        #expect(MCPProtocolVersion.profile(for: "2026-07-28")?.resourceNotFoundCode == -32602)
    }
}
