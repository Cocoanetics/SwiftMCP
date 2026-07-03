//
//  MRTR.swift
//  SwiftMCP
//
//  Multi Round-Trip Requests (MCP 2026-07-28, SEP-2322): the modern replacement
//  for live server→client requests. A `tools/call` / `resources/read` /
//  `prompts/get` that needs client input answers with an ``InputRequiredResult``;
//  the client gathers the inputs and retries the original request (new JSON-RPC
//  id) with `params.inputResponses` keyed by the same ids, echoing
//  `params.requestState` verbatim.
//

import Foundation

/// One server→client input request embedded in an ``InputRequiredResult`` —
/// an `elicitation/create`, `sampling/createMessage`, or `roots/list` request
/// carried as `{method, params}` (no JSON-RPC envelope).
public struct InputRequest: Codable, Sendable {
    public var method: String
    public var params: JSONValue?

    public init(method: String, params: JSONValue?) {
        self.method = method
        self.params = params
    }
}

/// The `input_required` result a modern server returns when it needs client
/// input to finish a request. At least one of `inputRequests` / `requestState`
/// is always present (SwiftMCP always sends both).
public struct InputRequiredResult: Codable, Sendable {
    /// Discriminator: always `"input_required"`.
    public var resultType: String

    /// Server-assigned ids → the input requests the client must fulfill before
    /// retrying. Ids are unique within the scope of the originating request.
    public var inputRequests: [String: InputRequest]?

    /// Opaque, integrity-protected server state the client echoes verbatim on
    /// retry. Clients must not inspect or modify it.
    public var requestState: String?

    public init(
        resultType: String = "input_required",
        inputRequests: [String: InputRequest]? = nil,
        requestState: String? = nil
    ) {
        self.resultType = resultType
        self.inputRequests = inputRequests
        self.requestState = requestState
    }
}

/// The result shape of a `roots/list` reply (`{ "roots": [...] }`), used to
/// decode an MRTR `inputResponses` entry for a `roots/list` input request.
public struct RootsListResult: Codable, Sendable {
    public var roots: [Root]

    public init(roots: [Root]) {
        self.roots = roots
    }
}

/// Internal control-flow signal thrown by the era-aware `sample`/`elicit`/
/// `listRoots` when a modern request needs client input that isn't present in
/// the retry's `inputResponses`. The MRTR-eligible dispatch handlers catch it
/// and answer with an ``InputRequiredResult``; it must never escape to a
/// generic error path for those methods.
struct InputRequiredSignal: Error {
    /// The deterministic per-execution ordinal id (`input-N`) — the same call
    /// site yields the same id on re-execution, so the retry lookup matches.
    let id: String

    /// The input request to surface to the client.
    let request: InputRequest
}

/// Thrown when a retry's `inputResponses` entry exists but cannot be decoded
/// into the shape the call site expects — a malformed client response (or an
/// ordinal skew from a handler that isn't deterministic across re-executions).
/// The MRTR handlers convert it to the spec's `-32602` protocol error.
struct MRTRInvalidInputResponse: Error {
    let id: String
    let underlying: Error
}
