import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - URLSession Delegate

/// A URLSession delegate that prevents automatic redirect following,
/// allowing the proxy to return redirect responses to the client.
final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
	func urlSession(
		_ session: URLSession,
		task: URLSessionTask,
		willPerformHTTPRedirection response: HTTPURLResponse,
		newRequest request: URLRequest,
		completionHandler: @escaping (URLRequest?) -> Void
	) {
		completionHandler(nil) // Don't follow redirects
	}
}
