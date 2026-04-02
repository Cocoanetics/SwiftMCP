import Foundation

extension AsyncStream<Data>: RouteBody {
	/// Forward the stream as-is — no buffering.
	static func collect(from stream: AsyncStream<Data>) async -> AsyncStream<Data> {
		stream
	}
}
