import Foundation

public extension BinaryInteger {
    static func convert<T>(from value: T) -> Self? {
        if let exact = value as? Self {
            return exact
        }
        if let boolValue = value as? Bool {
            return Self(boolValue ? 1 : 0)
        }
        if let intValue = value as? any BinaryInteger {
            return Self(intValue) // This should generally work if Self can represent intValue
        }
        if let floatValue = value as? any BinaryFloatingPoint {
            let doubleValue = Double(floatValue) // Convert to Double for consistent checks
            // Ensure no precision is lost for integers
            if doubleValue.truncatingRemainder(dividingBy: 1.0) == 0 {
                return Self(exactly: doubleValue) // Attempt to initialize from Double
            }
        }
        // Attempt to convert from String
        if let stringValue = value as? String {
            // Try initializing from common integer string representations
            if let intVal = Int(stringValue) { return Self(exactly: intVal) }
            if let int64Val = Int64(stringValue) { return Self(exactly: int64Val) }
        // Add UInt, UInt64 etc. if necessary and if Self supports them
        // Fallback to a general radix-based init if available and needed, though less common here.
        }
        return nil
    }
}

public extension BinaryFloatingPoint {
    static func convert<T>(from value: T) -> Self? {
        if let exact = value as? Self {
            return exact
        }
        if let boolValue = value as? Bool {
            return Self(boolValue ? 1.0 : 0.0)
        }
        if let intValue = value as? any BinaryInteger {
            return Self(intValue)
        }
        if let floatValue = value as? any BinaryFloatingPoint {
            return Self(floatValue) // Direct conversion if T is also some BinaryFloatingPoint
        }
        // Attempt to convert from String
        if let stringValue = value as? String {
            // Convert string to Double first, then to Self.
            // This is a common strategy as Double(String) is robust.
            if let doubleVal = Double(stringValue) {
                return Self(doubleVal) // Assumes Self can be initialized from Double
            }
        }
        return nil
    }
} 