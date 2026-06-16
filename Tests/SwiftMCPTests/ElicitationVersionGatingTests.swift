import Foundation
import Testing
@testable import SwiftMCP

/// `elicitation/create` is a 2025-06-18 feature. The server must gate it on the
/// *negotiated* protocol version — not merely the client's advertised
/// capability — so a session that negotiated an earlier revision can never be
/// driven into an elicitation round-trip, even if the client over-declares the
/// capability.
@Suite("Elicitation version gating")
struct ElicitationVersionGatingTests {

    /// A Sendable summary of how `elicit` resolved, so the assertion can run
    /// outside the `Session.work` closure without moving a non-Sendable error
    /// across the boundary.
    private enum Outcome: Sendable, Equatable {
        case returned
        case versionGated(feature: String, version: String)
        case clientUnsupported
        case other(String)
    }

    private let schema = JSONSchema.object(JSONSchema.Object(
        properties: [
            "name": .string(title: nil, description: "Name", format: nil, minLength: nil, maxLength: nil)
        ],
        required: ["name"]
    ))

    /// Calls `elicit` with `Session.current` bound to a session that negotiated
    /// `version` (when non-nil) and advertised `elicitation` per
    /// `clientSupportsElicitation`, reducing the result to an ``Outcome``.
    private func elicitOutcome(
        negotiating version: String?,
        clientSupportsElicitation: Bool
    ) async -> Outcome {
        let session = Session(id: UUID())
        if let version {
            await session.setNegotiatedProtocolVersion(version)
        }
        if clientSupportsElicitation {
            await session.setClientCapabilities(
                ClientCapabilities(elicitation: ClientCapabilities.ElicitationCapabilities())
            )
        }

        let context = RequestContext(message: .request(id: 1, method: "tools/call"))
        let schema = schema
        return await session.work { _ in
            do {
                _ = try await context.elicit(message: "Provide your name", schema: schema)
                return .returned
            } catch MCPServerError.featureUnavailableInNegotiatedVersion(let feature, let version) {
                return .versionGated(feature: feature.rawValue, version: version)
            } catch MCPServerError.clientHasNoElicitationSupport {
                return .clientUnsupported
            } catch {
                return .other(String(describing: error))
            }
        }
    }

    @Test("A 2025-03-26 session is refused even when the client advertises elicitation")
    func refusedForPre0618() async {
        let outcome = await elicitOutcome(negotiating: "2025-03-26", clientSupportsElicitation: true)
        #expect(outcome == .versionGated(feature: MCPFeature.elicitation.rawValue, version: "2025-03-26"))
    }

    @Test(
        "Revisions that include elicitation clear the version gate",
        arguments: ["2025-06-18", "2025-11-25"]
    )
    func passesVersionGateForElicitationVersions(_ version: String) async {
        // With no elicitation capability the version gate must pass and the
        // *capability* check must be what rejects — proving the gate does not
        // fire for revisions that genuinely include elicitation.
        let outcome = await elicitOutcome(negotiating: version, clientSupportsElicitation: false)
        #expect(outcome == .clientUnsupported)
    }

    @Test("A session without a negotiated version is not version-gated")
    func ungatedWithoutNegotiation() async {
        // Preserves the pre-gating behavior for sessions that never negotiated a
        // legacy version: it falls through to the capability check.
        let outcome = await elicitOutcome(negotiating: nil, clientSupportsElicitation: false)
        #expect(outcome == .clientUnsupported)
    }
}
