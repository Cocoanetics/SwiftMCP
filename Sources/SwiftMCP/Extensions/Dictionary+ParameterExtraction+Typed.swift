import Foundation

// MARK: - Typed Primitive Extraction (Bool / Date / URL / UUID / Data)
public extension Dictionary where Key == String, Value == JSONValue {

    func extractDate(named name: String) throws -> Date {
        guard let jsonValue = self[name] else {
            preconditionFailure("Failed to retrieve value for parameter \(name)")
        }

        if let stringValue = jsonValue.stringValue {
            let isoFormatter = ISO8601DateFormatter()
            if let date = isoFormatter.date(from: stringValue) {
                return date
            }
            if let timestampDouble = Double(stringValue) {
                return Date(timeIntervalSince1970: timestampDouble)
            }
        }

        if let timestampDouble = jsonValue.doubleValue {
            return Date(timeIntervalSince1970: timestampDouble)
        }

        throw invalidArgumentType(
            parameterName: name,
            expectedType: "ISO 8601 Date",
            actualValue: jsonValue
        )
    }

    func extractBool(named name: String) throws -> Bool {
        guard let jsonValue = self[name] else {
            preconditionFailure("Failed to retrieve value for parameter \(name)")
        }

        if let boolValue = jsonValue.boolValue {
            return boolValue
        }

        if let stringValue = jsonValue.stringValue {
            switch stringValue.lowercased() {
            case "true":
                return true
            case "false":
                return false
            default:
                throw invalidArgumentType(parameterName: name, expectedType: "Bool", actualValue: jsonValue)
            }
        }

        throw invalidArgumentType(parameterName: name, expectedType: "Bool", actualValue: jsonValue)
    }

    func extractURL(named name: String) throws -> URL {
        guard let jsonValue = self[name] else {
            preconditionFailure("Failed to retrieve value for parameter \(name)")
        }

        if let stringValue = jsonValue.stringValue,
           let url = URL(string: stringValue) {
            return url
        }

        throw invalidArgumentType(parameterName: name, expectedType: "URL", actualValue: jsonValue)
    }

    func extractUUID(named name: String) throws -> UUID {
        guard let jsonValue = self[name] else {
            preconditionFailure("Failed to retrieve value for parameter \(name)")
        }

        if let stringValue = jsonValue.stringValue,
           let uuid = UUID(uuidString: stringValue) {
            return uuid
        }

        throw invalidArgumentType(parameterName: name, expectedType: "UUID", actualValue: jsonValue)
    }

    func extractData(named name: String) throws -> Data {
        guard let jsonValue = self[name] else {
            preconditionFailure("Failed to retrieve value for parameter \(name)")
        }

        if let stringValue = jsonValue.stringValue,
           let data = Data(base64Encoded: stringValue) {
            return data
        }

        throw invalidArgumentType(parameterName: name, expectedType: "Base64-encoded Data", actualValue: jsonValue)
    }
}
