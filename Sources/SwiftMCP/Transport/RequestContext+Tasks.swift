//
//  RequestContext+Tasks.swift
//  SwiftMCP
//
//  Mid-flight input resolution for tools running inside an official Tasks-
//  extension task (`tasks/get` / `tasks/update`).
//

import Foundation

extension RequestContext {
    /// Resolves a server→client input through an in-flight Tasks-extension task.
    func resolveTaskInput<Response: Decodable & Sendable>(
        task: MCPTaskRecord,
        method: String,
        params: JSONValue?,
        as type: Response.Type
    ) async throws -> Response {
        let answer = try await task.awaitInput(method: method, params: params)
        do {
            return try answer.decoded(type)
        } catch {
            throw MRTRInvalidInputResponse(id: method, underlying: error)
        }
    }

    /// Task-path sampling, or `nil` when no task is in flight.
    func sampleViaTaskIfPresent(
        _ request: SamplingCreateMessageRequest
    ) async throws -> SamplingCreateMessageResponse? {
        guard let task = MCPTaskRecord.current else { return nil }
        guard await effectiveClientCapabilities?.sampling != nil else {
            throw MCPServerError.clientHasNoSamplingSupport
        }
        let params = try JSONDictionary(encoding: request)
        return try await resolveTaskInput(
            task: task, method: "sampling/createMessage", params: .object(params),
            as: SamplingCreateMessageResponse.self
        )
    }

    /// Task-path elicitation, or `nil` when no task is in flight.
    func elicitViaTaskIfPresent(
        _ request: ElicitationCreateRequest
    ) async throws -> ElicitationCreateResponse? {
        guard let task = MCPTaskRecord.current else { return nil }
        guard await effectiveClientCapabilities?.elicitation != nil else {
            throw MCPServerError.clientHasNoElicitationSupport
        }
        let params = try JSONDictionary(encoding: request)
        return try await resolveTaskInput(
            task: task, method: "elicitation/create", params: .object(params),
            as: ElicitationCreateResponse.self
        )
    }
}
