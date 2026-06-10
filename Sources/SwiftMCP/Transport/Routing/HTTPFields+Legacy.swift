#if Server
import HTTPTypes

extension HTTPFields {
	/// Build `HTTPFields` from legacy name/value pairs.
	///
	/// Pairs whose name is not a valid HTTP field token (per RFC 9110) are
	/// dropped rather than crashing — the same defensive posture the old
	/// array-based code had, but now the surviving fields are validated.
	init(legacyPairs pairs: [(String, String)]) {
		self.init()
		for (name, value) in pairs {
			guard let fieldName = HTTPField.Name(name) else { continue }
			append(HTTPField(name: fieldName, value: value))
		}
	}

	/// The fields as legacy name/value pairs, preserving original casing and order.
	var legacyPairs: [(String, String)] {
		map { ($0.name.rawName, $0.value) }
	}
}
#endif
