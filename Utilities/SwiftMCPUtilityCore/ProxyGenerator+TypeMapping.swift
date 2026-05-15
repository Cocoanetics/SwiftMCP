import Foundation
import SwiftMCP

extension ProxyGenerator {
    struct SwiftTypeInfo {
        let typeName: String
        let needsEncoding: Bool
    }

    static func swiftTypeInfo(for type: Sendable.Type) -> SwiftTypeInfo? {
        if let info = scalarSwiftTypeInfo(for: type) {
            return info
        }
        if let info = integerSwiftTypeInfo(for: type) {
            return info
        }
        if let info = encodedScalarSwiftTypeInfo(for: type) {
            return info
        }
        if let info = arraySwiftTypeInfo(for: type) {
            return info
        }
        return nil
    }

    private static func scalarSwiftTypeInfo(for type: Sendable.Type) -> SwiftTypeInfo? {
        if type == String.self {
            return SwiftTypeInfo(typeName: "String", needsEncoding: false)
        }
        if type == Double.self {
            return SwiftTypeInfo(typeName: "Double", needsEncoding: false)
        }
        if type == Float.self {
            return SwiftTypeInfo(typeName: "Float", needsEncoding: false)
        }
        if type == Bool.self {
            return SwiftTypeInfo(typeName: "Bool", needsEncoding: false)
        }
        return nil
    }

    private static func integerSwiftTypeInfo(for type: Sendable.Type) -> SwiftTypeInfo? {
        if type == Int.self {
            return SwiftTypeInfo(typeName: "Int", needsEncoding: false)
        }
        if type == Int8.self {
            return SwiftTypeInfo(typeName: "Int8", needsEncoding: false)
        }
        if type == Int16.self {
            return SwiftTypeInfo(typeName: "Int16", needsEncoding: false)
        }
        if type == Int32.self {
            return SwiftTypeInfo(typeName: "Int32", needsEncoding: false)
        }
        if type == Int64.self {
            return SwiftTypeInfo(typeName: "Int64", needsEncoding: false)
        }
        if type == UInt.self {
            return SwiftTypeInfo(typeName: "UInt", needsEncoding: false)
        }
        if type == UInt8.self {
            return SwiftTypeInfo(typeName: "UInt8", needsEncoding: false)
        }
        if type == UInt16.self {
            return SwiftTypeInfo(typeName: "UInt16", needsEncoding: false)
        }
        if type == UInt32.self {
            return SwiftTypeInfo(typeName: "UInt32", needsEncoding: false)
        }
        if type == UInt64.self {
            return SwiftTypeInfo(typeName: "UInt64", needsEncoding: false)
        }
        return nil
    }

    private static func encodedScalarSwiftTypeInfo(for type: Sendable.Type) -> SwiftTypeInfo? {
        if type == Date.self {
            return SwiftTypeInfo(typeName: "Date", needsEncoding: true)
        }
        if type == URL.self {
            return SwiftTypeInfo(typeName: "URL", needsEncoding: true)
        }
        if type == UUID.self {
            return SwiftTypeInfo(typeName: "UUID", needsEncoding: true)
        }
        if type == Data.self {
            return SwiftTypeInfo(typeName: "Data", needsEncoding: true)
        }
        return nil
    }

    private static func arraySwiftTypeInfo(for type: Sendable.Type) -> SwiftTypeInfo? {
        if type == [String].self {
            return SwiftTypeInfo(typeName: "[String]", needsEncoding: false)
        }
        if type == [Int].self {
            return SwiftTypeInfo(typeName: "[Int]", needsEncoding: false)
        }
        if type == [Double].self {
            return SwiftTypeInfo(typeName: "[Double]", needsEncoding: false)
        }
        if type == [Float].self {
            return SwiftTypeInfo(typeName: "[Float]", needsEncoding: false)
        }
        if type == [Bool].self {
            return SwiftTypeInfo(typeName: "[Bool]", needsEncoding: false)
        }
        if type == [Date].self {
            return SwiftTypeInfo(typeName: "[Date]", needsEncoding: true)
        }
        if type == [URL].self {
            return SwiftTypeInfo(typeName: "[URL]", needsEncoding: true)
        }
        if type == [UUID].self {
            return SwiftTypeInfo(typeName: "[UUID]", needsEncoding: true)
        }
        if type == [Data].self {
            return SwiftTypeInfo(typeName: "[Data]", needsEncoding: true)
        }
        return nil
    }

    static func swiftTypeInfo(for schema: JSONSchema) -> SwiftTypeInfo {
        switch schema {
        case .string(_, _, let format, _, _, _):
            return stringSchemaSwiftTypeInfo(format: format)
        case .number:
            return SwiftTypeInfo(typeName: "Double", needsEncoding: false)
        case .boolean:
            return SwiftTypeInfo(typeName: "Bool", needsEncoding: false)
        case .array(let items, _, _, _):
            let elementInfo = swiftTypeInfo(for: items)
            return SwiftTypeInfo(typeName: "[\(elementInfo.typeName)]", needsEncoding: elementInfo.needsEncoding)
        case .object:
            return SwiftTypeInfo(typeName: "JSONDictionary", needsEncoding: false)
        case .enum:
            return SwiftTypeInfo(typeName: "String", needsEncoding: false)
        case .oneOf:
            return SwiftTypeInfo(typeName: "String", needsEncoding: false)
        }
    }

    private static func stringSchemaSwiftTypeInfo(format: String?) -> SwiftTypeInfo {
        switch format ?? "" {
        case "date-time":
            return SwiftTypeInfo(typeName: "Date", needsEncoding: true)
        case "uri":
            return SwiftTypeInfo(typeName: "URL", needsEncoding: true)
        case "uuid":
            return SwiftTypeInfo(typeName: "UUID", needsEncoding: true)
        case "byte":
            return SwiftTypeInfo(typeName: "Data", needsEncoding: true)
        default:
            return SwiftTypeInfo(typeName: "String", needsEncoding: false)
        }
    }
}
