import Foundation

// MARK: - Numeric Parameter Extraction
public extension Dictionary where Key == String, Value == JSONValue {

    func extractNumber<N: BinaryInteger>(named name: String, as type: N.Type = N.self) throws -> N {
        guard let jsonValue = self[name] else {
            preconditionFailure("Failed to retrieve value for parameter \(name)")
        }

        if let value = N.convert(from: jsonValue) {
            return value
        }

        throw invalidArgumentType(
            parameterName: name,
            expectedType: String(describing: N.self),
            actualValue: jsonValue
        )
    }

    func extractNumber<N: BinaryFloatingPoint>(named name: String, as type: N.Type = N.self) throws -> N {
        guard let jsonValue = self[name] else {
            preconditionFailure("Failed to retrieve value for parameter \(name)")
        }

        if let value = N.convert(from: jsonValue) {
            return value
        }

        throw invalidArgumentType(
            parameterName: name,
            expectedType: String(describing: N.self),
            actualValue: jsonValue
        )
    }

    func extractNumberArray<N: BinaryInteger>(named name: String, as type: N.Type = N.self) throws -> [N] {
        guard let jsonValue = self[name] else {
            preconditionFailure("Failed to retrieve value for parameter \(name)")
        }
        guard case let .array(values) = jsonValue else {
            throw invalidArgumentType(
                parameterName: name,
                expectedType: "Array of \(String(describing: N.self))",
                actualValue: jsonValue
            )
        }

        return try values.map { element in
            guard let converted = N.convert(from: element) else {
                throw invalidArgumentType(
                    parameterName: name,
                    expectedType: String(describing: N.self),
                    actualValue: element
                )
            }
            return converted
        }
    }

    func extractNumberArray<N: BinaryFloatingPoint>(named name: String, as type: N.Type = N.self) throws -> [N] {
        guard let jsonValue = self[name] else {
            preconditionFailure("Failed to retrieve value for parameter \(name)")
        }
        guard case let .array(values) = jsonValue else {
            throw invalidArgumentType(
                parameterName: name,
                expectedType: "Array of \(String(describing: N.self))",
                actualValue: jsonValue
            )
        }

        return try values.map { element in
            guard let converted = N.convert(from: element) else {
                throw invalidArgumentType(
                    parameterName: name,
                    expectedType: String(describing: N.self),
                    actualValue: element
                )
            }
            return converted
        }
    }

    func extractOptionalNumber<N: BinaryInteger>(named name: String, as type: N.Type = N.self) throws -> N? {
        guard self[name] != nil else { return nil }
        return try extractNumber(named: name, as: type)
    }

    func extractOptionalNumber<N: BinaryFloatingPoint>(named name: String, as type: N.Type = N.self) throws -> N? {
        guard self[name] != nil else { return nil }
        return try extractNumber(named: name, as: type)
    }

    func extractOptionalNumberArray<N: BinaryInteger>(named name: String, as type: N.Type = N.self) throws -> [N]? {
        guard self[name] != nil else { return nil }
        return try extractNumberArray(named: name, as: type)
    }

    func extractOptionalNumberArray<N: BinaryFloatingPoint>(
        named name: String,
        as type: N.Type = N.self
    ) throws -> [N]? {
        guard self[name] != nil else { return nil }
        return try extractNumberArray(named: name, as: type)
    }

    func extractInt(named name: String) throws -> Int {
        try extractNumber(named: name, as: Int.self)
    }

    func extractDouble(named name: String) throws -> Double {
        try extractNumber(named: name, as: Double.self)
    }

    func extractFloat(named name: String) throws -> Float {
        try extractNumber(named: name, as: Float.self)
    }

    func extractIntArray(named name: String) throws -> [Int] {
        try extractNumberArray(named: name, as: Int.self)
    }

    func extractDoubleArray(named name: String) throws -> [Double] {
        try extractNumberArray(named: name, as: Double.self)
    }

    func extractFloatArray(named name: String) throws -> [Float] {
        try extractNumberArray(named: name, as: Float.self)
    }
}
