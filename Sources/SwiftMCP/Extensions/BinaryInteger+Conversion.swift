import Foundation

extension BinaryInteger {
/// Attempts to convert the given value to `Self`.
/// Returns `nil` if the conversion is not possible.
    static func convert(from value: Any) -> Self? {
        if let this = value as? Self {
            return this
        }
        if let boolValue = value as? Bool {
            return boolValue ? 1 : 0
        }
        if let integerValue = value as? any BinaryInteger {
            return Self(exactly: integerValue)
        }
        if let floatingValue = value as? any BinaryFloatingPoint {
            return Self(exactly: floatingValue)
        }
        return nil
    }
}
