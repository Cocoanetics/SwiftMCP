import Foundation

/// Protocol for types that can serve as the body of an `HTTPRouteRequest`.
///
/// Conforming types define how to prepare the body from a raw `AsyncStream<Data>`:
/// - `Data?` collects the stream into buffered data.
/// - `AsyncStream<Data>` forwards the stream as-is.
protocol RouteBody: Sendable {
	/// Prepare the body value from the raw body chunk stream.
	static func collect(from stream: AsyncStream<Data>) async -> Self
}
