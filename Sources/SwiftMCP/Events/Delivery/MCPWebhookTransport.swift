#if Server
//
//  MCPWebhookTransport.swift
//  SwiftMCP
//
//  HTTP transport and DNS resolution used by webhook delivery.
//

import Foundation
import SwiftCross
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Bionic)
import Bionic
#endif

/// Sends one signed webhook POST. Implementations must not follow redirects.
public protocol MCPWebhookTransport: Sendable {
    func post(url: URL, headers: [String: String], body: Data, timeout: TimeInterval) async throws -> MCPWebhookResponse
}

/// Default transport: `URLSession` with redirects refused, so a 3xx surfaces as a
/// response instead of leading the request to an unvetted host.
///
/// `URLSession` cannot pin the connection to the addresses the policy vetted, so
/// the engine resolves and checks the host immediately before every attempt;
/// a rebinding window of that length remains.
public struct URLSessionWebhookTransport: MCPWebhookTransport {
    public init() {}

    public func post(
        url: URL, headers: [String: String], body: Data, timeout: TimeInterval
    ) async throws -> MCPWebhookResponse {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.httpBody = body
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.httpShouldSetCookies = false
        let collector = HeadOnlyCollector()
        let session = URLSession(configuration: configuration, delegate: collector, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        let http: HTTPURLResponse = try await withCheckedThrowingContinuation { continuation in
            collector.continuation = continuation
            session.dataTask(with: request).resume()
        }
        let retryAfter = Self.parseRetryAfter(http.value(forHTTPHeaderField: "Retry-After"))
        return MCPWebhookResponse(statusCode: http.statusCode, retryAfter: retryAfter)
    }

    /// Parses `Retry-After` in its delay-seconds or HTTP-date form, as seconds from `now`.
    static func parseRetryAfter(_ value: String?, now: Date = Date()) -> TimeInterval? {
        guard let value = value?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
        if let seconds = TimeInterval(value) { return max(0, seconds) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: value).map { max(0, $0.timeIntervalSince(now)) }
    }
}

/// Resolves a request with its response head and cancels the transfer there, so a
/// subscriber-controlled endpoint cannot make the server buffer its response body.
/// Redirects are refused.
private final class HeadOnlyCollector: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    var continuation: CheckedContinuation<HTTPURLResponse, Error>?
    private var response: HTTPURLResponse?
    private var finished = false

    private func finish(_ result: Result<HTTPURLResponse, Error>) {
        guard !finished else { return }
        finished = true
        continuation?.resume(with: result)
        continuation = nil
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        if let http = response as? HTTPURLResponse {
            self.response = http
            finish(.success(http))
        }
        completionHandler(.cancel)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let response { finish(.success(response)) } else { finish(.failure(error ?? URLError(.badServerResponse))) }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
#endif

#if Server && (canImport(Darwin) || canImport(Glibc) || canImport(Musl) || canImport(Bionic))
extension WebhookURLPolicy {
    /// Resolves a host with `getaddrinfo` to numeric address strings (IPv4 and IPv6).
    public static let systemResolver: Resolver = { host in
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                var hints = addrinfo()
                hints.ai_family = AF_UNSPEC
                var list: UnsafeMutablePointer<addrinfo>?
                let status = getaddrinfo(host, nil, &hints, &list)
                guard status == 0, let first = list else {
                    continuation.resume(throwing: WebhookURLPolicyError.resolutionFailed(host))
                    return
                }
                defer { freeaddrinfo(list) }

                var addresses: [String] = []
                var cursor: UnsafeMutablePointer<addrinfo>? = first
                while let entry = cursor {
                    var buffer = [CChar](repeating: 0, count: 1025)
                    let length = socklen_t(buffer.count)
                    if let address = entry.pointee.ai_addr,
                       getnameinfo(address, entry.pointee.ai_addrlen, &buffer, length, nil, 0, NI_NUMERICHOST) == 0 {
                        let text = String(cString: buffer)
                        if !addresses.contains(text) { addresses.append(text) }
                    }
                    cursor = entry.pointee.ai_next
                }
                continuation.resume(returning: addresses)
            }
        }
    }
}
#elseif Server
extension WebhookURLPolicy {
    public static let systemResolver: Resolver = { host in throw WebhookURLPolicyError.resolutionFailed(host) }
}
#endif
