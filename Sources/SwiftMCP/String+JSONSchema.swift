import Foundation

extension String {
    /// Converts a Swift type string to its corresponding MCP JSON Schema type
   public var JSONSchemaType: String {
        switch self {
        case "Int", "UInt", "Int8", "Int16", "Int32", "Int64",
             "UInt8", "UInt16", "UInt32", "UInt64", "Float", "Double":
            return "number"
        case "Bool":
            return "boolean"
        case "String", "Character":
            return "string"
        case "Array", "[Any]", "[String]", "[Int]", "[Double]", "Array<T>":
            return "array"
        case "Dictionary", "[String: Any]", "[String: String]", "[String: Int]":
            return "object"
        case "Optional":
            return "null"
        case "Data":
            return "string" // Base64-encoded data should use "string" with format
        default:
            return "string" // Default to string for unknown types
        }
    }
}
