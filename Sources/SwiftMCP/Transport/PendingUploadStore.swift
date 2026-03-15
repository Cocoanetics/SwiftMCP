import Foundation

/// Tracks pending content-ID uploads for a session.
///
/// When a tool call contains `cid:` placeholders for Data parameters,
/// the server registers expectations here. The upload endpoint fulfills
/// them, resuming the tool call's parameter extraction.
actor PendingUploadStore {

    struct Expectation {
        let continuation: CheckedContinuation<Data, Error>
        let progressToken: JSONValue?
        let sessionID: UUID
        let expectedSize: Int?
    }

    private var expectations: [String: Expectation] = [:]  // cid → expectation

    /// Register a pending upload. Returns when the data arrives or the timeout fires.
    func waitForUpload(
        cid: String,
        progressToken: JSONValue?,
        sessionID: UUID,
        timeoutSeconds: Int = 300
    ) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            expectations[cid] = Expectation(
                continuation: continuation,
                progressToken: progressToken,
                sessionID: sessionID,
                expectedSize: nil
            )
        }
    }

    /// Fulfill a pending upload. Called by the upload endpoint.
    /// Returns the progress token associated with this CID (for progress notifications).
    @discardableResult
    func fulfill(cid: String, data: Data) -> JSONValue? {
        guard let expectation = expectations.removeValue(forKey: cid) else {
            return nil
        }
        expectation.continuation.resume(returning: data)
        return expectation.progressToken
    }

    /// Fail a pending upload (e.g. on cancellation or timeout).
    func fail(cid: String, error: Error) {
        guard let expectation = expectations.removeValue(forKey: cid) else {
            return
        }
        expectation.continuation.resume(throwing: error)
    }

    /// Cancel all pending uploads for a session.
    func cancelAll(sessionID: UUID, error: Error) {
        let matching = expectations.filter { $0.value.sessionID == sessionID }
        for (cid, expectation) in matching {
            expectations.removeValue(forKey: cid)
            expectation.continuation.resume(throwing: error)
        }
    }

    /// Check if a CID is expected.
    func isExpected(cid: String) -> Bool {
        expectations[cid] != nil
    }

    /// Get the progress token for a CID (for sending progress notifications during upload).
    func progressToken(for cid: String) -> JSONValue? {
        expectations[cid]?.progressToken
    }
}
