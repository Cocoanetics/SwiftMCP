//
//  MCPServer+MRTR.swift
//  SwiftMCP
//
//  The MRTR dispatch glue shared by the three eligible handlers (`tools/call`,
//  `resources/read`, `prompts/get`): pre-execution verification/merging of a
//  retry's `requestState` + `inputResponses`, and conversion of an
//  ``InputRequiredSignal`` into an `input_required` response.
//
//  This file lives in the always-on core; the signed-state machinery needs
//  swift-crypto, which only the `Server` trait links, so those parts are gated
//  `#if Server`. Without it, MRTR degrades gracefully: `input_required` is
//  emitted with `inputRequests` only (no `requestState` — the spec allows
//  either field alone), which covers single-input round trips; multi-input
//  tools then rely on the spec's re-request loop instead of the accumulator.
//

import Foundation

extension MCPServer {

    /// Pre-execution MRTR step for an eligible handler: ingests a retry's
    /// `requestState` / `inputResponses` into the context's execution state.
    ///
    /// Returns an error response when the echoed state fails verification
    /// (signature, expiry, principal, or originating-request digest — the state
    /// is attacker-controlled input), `nil` to proceed with execution.
    internal func mrtrPrepareExecution(
        _ request: JSONRPCMessage.JSONRPCRequestData
    ) async -> JSONRPCMessage? {
        guard let context = RequestContext.current,
              await context.protocolProfile.has(.mrtr) else {
            return nil
        }

        var merged: [String: JSONValue] = [:]

        if let state = context.requestState {
            #if Server
            guard let payloadData = mrtrRequestStateSigner.verify(state),
                  let payload = try? JSONDecoder().decode(MRTRRequestStatePayload.self, from: payloadData),
                  payload.exp > Date().timeIntervalSince1970,
                  payload.principal == MRTRRequestState.principal(accessToken: context.meta?.accessToken),
                  payload.requestDigest == MRTRRequestState.requestDigest(
                    method: request.method, params: request.params
                  ) else {
                return JSONRPCMessage.errorResponse(
                    id: request.id,
                    error: .init(code: -32602, message: "Invalid params: requestState failed verification")
                )
            }
            merged = payload.responses
            #else
            // Without the Server trait there is no signer: this build never
            // *issued* a requestState, so any echoed one cannot be genuine.
            return JSONRPCMessage.errorResponse(
                id: request.id,
                error: .init(code: -32602, message: "Invalid params: requestState failed verification")
            )
            #endif
        }

        if let inputResponses = context.inputResponses {
            merged.merge(inputResponses) { _, retry in retry }
        }

        if !merged.isEmpty {
            await context.mrtr.setResponses(merged)
        }
        return nil
    }

    /// Converts an ``MRTRInvalidInputResponse`` into the spec's `-32602`
    /// protocol error: a present-but-undecodable `inputResponses` entry is
    /// malformed client input, not a tool failure.
    internal func mrtrInvalidInputResponse(
        for invalid: MRTRInvalidInputResponse,
        request: JSONRPCMessage.JSONRPCRequestData
    ) -> JSONRPCMessage {
        JSONRPCMessage.errorResponse(
            id: request.id,
            error: .init(
                code: -32602,
                message: "Invalid params: malformed inputResponse for '\(invalid.id)'"
            )
        )
    }

    /// Converts an ``InputRequiredSignal`` into the `input_required` response
    /// for the originating request, signing the accumulated responses into
    /// `requestState` so the next retry can replay every earlier answer.
    internal func mrtrInputRequiredResponse(
        for signal: InputRequiredSignal,
        request: JSONRPCMessage.JSONRPCRequestData
    ) async -> JSONRPCMessage {
        var result = InputRequiredResult(inputRequests: [signal.id: signal.request])

        #if Server
        if let context = RequestContext.current {
            let now = Date().timeIntervalSince1970
            let payload = MRTRRequestStatePayload(
                iat: now,
                exp: now + MRTRRequestState.timeToLive,
                principal: MRTRRequestState.principal(accessToken: context.meta?.accessToken),
                requestDigest: MRTRRequestState.requestDigest(method: request.method, params: request.params),
                responses: await context.mrtr.allResponses()
            )
            if let payloadData = try? JSONEncoder().encode(payload) {
                result.requestState = mrtrRequestStateSigner.sign(payloadData)
            }
        }
        #endif

        do {
            let resultDict = try JSONDictionary(encoding: result)
            return JSONRPCMessage.response(id: request.id, result: .object(resultDict))
        } catch {
            return JSONRPCMessage.errorResponse(
                id: request.id,
                error: .init(code: -32603, message: "Failed to encode input_required result")
            )
        }
    }
}
