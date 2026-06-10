#if Client
import SwiftCross
import HTTPTypes

// Thin typed-name conveniences so the client sets/reads HTTP headers through the
// same validated `HTTPField.Name` constants the server routing layer uses,
// instead of bare string literals. The transfer still goes through `URLRequest`
// / `URLSession` (SwiftCross's shim on non-Apple platforms) — only the field
// *names* are funnelled through `HTTPTypes`.

extension URLRequest {
	/// Set a header value using a typed `HTTPField.Name` (uses the field's canonical raw name).
	mutating func setValue(_ value: String?, forHTTPField name: HTTPField.Name) {
		setValue(value, forHTTPHeaderField: name.rawName)
	}
}

extension HTTPURLResponse {
	/// Read a header value using a typed `HTTPField.Name`.
	func value(forHTTPField name: HTTPField.Name) -> String? {
		value(forHTTPHeaderField: name.rawName)
	}
}
#endif
