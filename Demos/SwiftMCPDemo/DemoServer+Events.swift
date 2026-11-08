import Foundation
import SwiftMCP

/// Payload delivered when a continuous-integration run fails (`ci.failed`).
@Schema
struct CIFailedPayload: Sendable, Codable {
    /// Pipeline or workflow that failed
    let pipeline: String
    /// Branch the failure occurred on
    let branch: String
    /// Commit SHA of the failed run
    let commit: String
    /// URL of the failed run's details page
    let url: String
    /// Short failure summary
    let message: String
}

@MCPExtension("Events")
extension DemoServer {
    /// A continuous-integration run failed.
    ///
    /// - Parameter pipeline: Only failures from this pipeline.
    /// - Parameter branch: Only failures on this branch.
    /// - Returns: Summary of the failed run for webhook delivery.
    @MCPEvent(name: "ci.failed", delivery: ["webhook"])
    func ciFailed(pipeline: String? = nil, branch: String? = nil) -> CIFailedPayload {
        CIFailedPayload(pipeline: "", branch: "", commit: "", url: "", message: "")
    }
}

#if Server
/// Webhook emission tools need the Server trait (`emit` / Crypto). The whole
/// extension is gated — not individual members — so `@MCPExtension` still
/// collects `@MCPTool` functions (it does not walk `IfConfigDecl` members).
@MCPExtension("EventEmission")
extension DemoServer {
    /// Emits a sample `ci.failed` event to every matching webhook subscription.
    /// - Returns: How many webhook deliveries were attempted
    @MCPTool(description: "Emits a sample ci.failed event to matching webhook subscribers")
    func emitCIFailed(
        pipeline: String,
        branch: String,
        commit: String,
        url: String,
        message: String
    ) async throws -> Int {
        await Self.logCall(
            function: "emitCIFailed",
            arguments: ["pipeline": pipeline, "branch": branch, "commit": commit]
        )
        let payload = CIFailedPayload(
            pipeline: pipeline,
            branch: branch,
            commit: commit,
            url: url,
            message: message
        )
        let outcomes = try await emit(
            "ci.failed",
            payload,
            attributes: .object([
                "pipeline": .string(pipeline),
                "branch": .string(branch)
            ])
        )
        return outcomes.count
    }
}
#endif

extension DemoServer {
    /// Creates a demo server with the Events extension registered
    /// (and EventEmission when the Server trait is enabled).
    static func makeWithEvents() async -> DemoServer {
        let server = DemoServer()
        await Events.register(in: server)
        #if Server
        await EventEmission.register(in: server)
        #endif
        return server
    }
}
