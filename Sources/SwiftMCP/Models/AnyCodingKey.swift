import Foundation

/**
 A coding key that can be initialized with any string value.
 Used for encoding and decoding dynamic property names in JSON schemas.
 */
struct AnyCodingKey: CodingKey {
    /// The string value of the coding key
    var stringValue: String
    /// The integer value of the coding key, if any
    var intValue: Int?

    /**
     Creates a coding key from a string value.

     - Parameter stringValue: The string value for the key
     - Returns: A coding key, or nil if the string value is invalid
     */
    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    /**
     Creates a coding key from an integer value.

     - Parameter intValue: The integer value for the key
     - Returns: A coding key, or nil if the integer value is invalid
     */
    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}
