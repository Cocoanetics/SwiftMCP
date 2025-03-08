import Foundation

extension String {
	/// Converts a Swift type string to its corresponding JSON Schema type
	public var JSONSchemaType: String {
		switch self {
		case "Int", "UInt", "Int8", "Int16", "Int32", "Int64",
			 "UInt8", "UInt16", "UInt32", "UInt64", "Float", "Double":
			return "number"
		case "Bool":
			return "boolean"
		case "String", "Character":
			return "string"
		case _ where self.hasPrefix("Array<") && self.hasSuffix(">"):
			return "array"
		case _ where self.hasPrefix("[") && self.hasSuffix("]"):
			return "array"
		case _ where self.hasPrefix("[") && self.contains(":") && self.hasSuffix("]"):
			return "object"
		case "Optional":
			return "null"
		case "Data":
			return "string" // Base64-encoded data should use "string" with format
		default:
			return "string" // Default to string for unknown types
		}
	}

	/// Extracts the element type from an array type string
	public var arrayElementType: String? {
		if self.hasPrefix("Array<") && self.hasSuffix(">") {
			let startIndex = self.index(self.startIndex, offsetBy: 6)
			let endIndex = self.index(self.endIndex, offsetBy: -1)
			return String(self[startIndex..<endIndex])
		} else if self.hasPrefix("[") && self.hasSuffix("]") {
			let startIndex = self.index(self.startIndex, offsetBy: 1)
			let endIndex = self.index(self.endIndex, offsetBy: -1)
			return String(self[startIndex..<endIndex])
		}
		return nil
	}
}
