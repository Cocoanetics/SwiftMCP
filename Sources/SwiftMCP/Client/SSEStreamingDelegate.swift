import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A `URLSession` delegate that feeds received bytes into an `AsyncStream`.
/// Used on Linux where `URLSession.bytes(for:)` is unavailable.
final class SSEStreamingDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lineContinuation: AsyncStream<String>.Continuation
    private var buffer = Data()
    private var responseHandler: ((URLResponse) -> Void)?

    /// The async stream of lines received from the SSE connection.
    let lines: AsyncStream<String>

    /// The HTTP response, available after the first data callback.
    private(set) var response: URLResponse?
    private let responseContinuation: CheckedContinuation<URLResponse, Never>?

    init(onResponse: @escaping (URLResponse) -> Void) {
        var cont: AsyncStream<String>.Continuation!
        self.lines = AsyncStream<String> { cont = $0 }
        self.lineContinuation = cont
        self.responseHandler = onResponse
        self.responseContinuation = nil
        super.init()
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        self.response = response
        responseHandler?(response)
        responseHandler = nil
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        buffer.append(data)

        // Split buffer on newlines and emit complete lines
        while let newlineRange = buffer.range(of: Data([0x0A])) {
            let lineData = buffer.subdata(in: buffer.startIndex..<newlineRange.lowerBound)
            buffer.removeSubrange(buffer.startIndex...newlineRange.lowerBound)

            // Strip trailing \r if present
            let cleanData: Data
            if lineData.last == 0x0D {
                cleanData = lineData.dropLast()
            } else {
                cleanData = lineData
            }

            let line = String(data: cleanData, encoding: .utf8) ?? ""
            lineContinuation.yield(line)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // Flush any remaining data in buffer as a final line
        if !buffer.isEmpty {
            let line = String(data: buffer, encoding: .utf8) ?? ""
            if !line.isEmpty {
                lineContinuation.yield(line)
            }
            buffer.removeAll()
        }
        lineContinuation.finish()
    }
}
