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
            .mrtr, .subscriptionsListen, .events,
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

    @Test("modern is described and negotiable, but not by initialize")
    func modernSupported() {
        #expect(MCPProtocolVersion.profile(for: MCPProtocolVersion.modern) != nil)
        #expect(MCPProtocolVersion.supported.contains(MCPProtocolVersion.modern))
        #expect(!MCPProtocolVersion.legacySupported.contains(MCPProtocolVersion.modern))
    }

    /// Guardrail: the server must only advertise versions it more or less fully
    /// supports. `initialize` negotiates legacy-era revisions only; the modern
    /// (`2026-07-28`) revision is the single modern entry, reached through
    /// `server/discover`. Adding a version here must be a deliberate change to
    /// this test.
    @Test("Only fully-supported versions are advertised")
    func advertisesOnlyImplementedVersions() {
        for version in MCPProtocolVersion.legacySupported {
            let profile = MCPProtocolVersion.profile(for: version)
            #expect(profile != nil, "advertised version \(version) has no profile")
            #expect(profile?.era == .legacy, "legacy version \(version) is not a legacy-era version")
        }
        #expect(MCPProtocolVersion.legacySupported.contains(MCPProtocolVersion.latest))
        #expect(MCPProtocolVersion.supported == MCPProtocolVersion.legacySupported.union([MCPProtocolVersion.modern]))
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

    @Test("Events is modern-only")
    func eventsIsModernOnly() {
        #expect(MCPProtocolVersion.profile(for: "2026-07-28")?.has(.events) == true)
        for version in ["2024-11-05", "2025-03-26", "2025-06-18", "2025-11-25"] {
            #expect(MCPProtocolVersion.profile(for: version)?.has(.events) == false)
        }
    }

    // MARK: - Events models

    @Test("EventDescriptor round-trips through JSON")
    func eventDescriptorRoundTrip() throws {
        let descriptor = EventDescriptor(
            name: "issue.opened",
            description: "An issue was opened",
            inputSchema: .object(.init(properties: ["repo": .string()], required: ["repo"])),
            payloadSchema: .object(.init(properties: ["number": .number()], required: [])),
            delivery: .init(modes: ["webhook"])
        )
        let data = try JSONEncoder().encode(descriptor)
        #expect(try JSONDecoder().decode(EventDescriptor.self, from: data) == descriptor)
    }

    @Test("Subscribe params and result round-trip through JSON")
    func subscribeRoundTrip() throws {
        let params = EventsSubscribeParams(
            name: "issue.opened",
            arguments: .object(["repo": .string("a/b")]),
            callbackUrl: "https://example.com/hook",
            subscriptionId: "sub-1",
            secret: "whsec_abc"
        )
        let paramsData = try JSONEncoder().encode(params)
        #expect(try JSONDecoder().decode(EventsSubscribeParams.self, from: paramsData) == params)

        let result = EventsSubscribeResult(
            subscriptionId: "sub-1", expiresAt: "2026-08-01T00:00:00Z", renewAfterMs: 60_000)
        let resultData = try JSONEncoder().encode(result)
        #expect(try JSONDecoder().decode(EventsSubscribeResult.self, from: resultData) == result)
    }

    @Test("List and unsubscribe models round-trip; constants match the spec")
    func listAndUnsubscribeRoundTrip() throws {
        let list = EventsListResult(events: [EventDescriptor(name: "e")], nextCursor: "c2")
        let listData = try JSONEncoder().encode(list)
        #expect(try JSONDecoder().decode(EventsListResult.self, from: listData) == list)

        let params = EventsUnsubscribeParams(subscriptionId: "sub-1")
        let data = try JSONEncoder().encode(params)
        #expect(try JSONDecoder().decode(EventsUnsubscribeParams.self, from: data) == params)

        #expect(MCPEventsExtension.listMethod == "events/list")
        #expect(StandardWebhooksHeader.signature == "webhook-signature")
    }

    // MARK: - Derived value facets

    @Test("Resource-not-found code follows the era")
    func resourceNotFoundCode() {
        #expect(MCPProtocolVersion.profile(for: "2025-11-25")?.resourceNotFoundCode == -32001)
        #expect(MCPProtocolVersion.profile(for: "2026-07-28")?.resourceNotFoundCode == -32602)
    }
}
