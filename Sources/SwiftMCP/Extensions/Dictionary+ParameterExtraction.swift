import Foundation

// MARK: - Dictionary to Decodable Conversion
extension Dictionary where Key == String {
    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        let data = try JSONSerialization.data(withJSONObject: self)
        return try JSONDecoder().decode(type, from: data)
    }
}

// MARK: - Array of Dictionaries to Array of Decodable Conversion
extension Array where Element == [String: Any] {
    func decode<T: Decodable>(_ type: T.Type) throws -> [T] {
        return try map { dict in
            let data = try JSONSerialization.data(withJSONObject: dict)
            return try JSONDecoder().decode(T.self, from: data)
        }
    }
    
    func decodeArray<T: Collection>(_ type: T.Type) throws -> [T.Element] where T.Element: Decodable {
        return try map { dict in
            let data = try JSONSerialization.data(withJSONObject: dict)
            return try JSONDecoder().decode(T.Element.self, from: data)
        }
    }
}

// MARK: - String to Decodable Conversion
extension String {
    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        guard let data = self.data(using: .utf8) else {
            throw MCPToolError.invalidArgumentType(
                parameterName: "jsonString",
                expectedType: "Valid JSON string",
                actualType: "Invalid JSON string"
            )
        }
        return try JSONDecoder().decode(type, from: data)
    }
}

// MARK: - Parameter Extraction Extensions for Dictionaries
public extension Dictionary where Key == String, Value == Sendable {
    
    /// Extracts a parameter of the specified type from the dictionary
    /// - Parameter name: The name of the parameter
    /// - Returns: The extracted value of type T
    /// - Throws: MCPToolError.invalidArgumentType if the parameter cannot be converted to type T
    func extractParameter<T>(named name: String) throws -> T {
        guard let anyValue = self[name] else {
            // this can never happen because arguments have already been enriched with default values
            preconditionFailure("Failed to retrieve value for parameter \(name)")
        }
        
        // try direct type casting
        if let value = anyValue as? T {
            return value
        }
        else if T.self == Bool.self {
            let boolValue = try extractBool(named: name)
            return boolValue as! T
        }
        else if T.self == Date.self {
            // Handle Date type using the new extractDate method
            let date = try extractDate(named: name)
            return date as! T
        }
        else if T.self == URL.self {
            // Handle URL type using the new extractURL method
            let url = try extractURL(named: name)
            return url as! T
        }
        else if let caseType = T.self as? any CaseIterable.Type {
            guard let string = anyValue as? String else {
                throw MCPToolError.invalidArgumentType(
                    parameterName: name,
                    expectedType: "String",
                    actualType: String(describing: Swift.type(of: anyValue))
                )
            }
            
            let caseLabels = caseType.caseLabels
            
            guard let index = caseLabels.firstIndex(of: string) else {
                throw MCPToolError.invalidEnumValue(parameterName: name, expectedValues: caseLabels, actualValue: string)
            }
            
            guard let allCases = caseType.allCases as? [T] else {
                // This can never happen because the result of CaseIterable is an array of the enum type
                preconditionFailure()
            }
            
            // return the actual enum case value that matches the string label
            return allCases[index]
        }
        else if let schemaType = T.self as? any SchemaRepresentable.Type,
                let decodableType = schemaType as? Decodable.Type {
            if let dict = anyValue as? [String: Any] {
                return try dict.decode(decodableType.self) as! T
            } else if let array = anyValue as? [[String: Any]] {
                return try array.decode(decodableType.self) as! T
            } else if let jsonString = anyValue as? String {
                // Handle JSON string using the new decode method
                if let result = try jsonString.decode(decodableType) as? T {
                    return result
                } else {
                    throw MCPToolError.invalidArgumentType(
                        parameterName: name,
                        expectedType: String(describing: T.self),
                        actualType: "Decoded object could not be cast to \(String(describing: T.self))"
                    )
                }
            } else {
                throw MCPToolError.invalidArgumentType(
                    parameterName: name,
                    expectedType: "Dictionary, Array of Dictionaries, or JSON string",
                    actualType: String(describing: Swift.type(of: anyValue))
                )
            }
        }
        else {
            throw MCPToolError.invalidArgumentType(
                parameterName: name,
                expectedType: String(describing: T.self),
                actualType: String(describing: Swift.type(of: anyValue))
            )
        }
    }
	
	/// Extracts a parameter of the specified type from the dictionary, returning nil if the parameter is missing or invalid
	/// - Parameter name: The name of the parameter
	/// - Returns: The extracted value of type T, or nil if the parameter is missing or invalid
	func extractOptionalParameter<T>(named name: String) throws -> T? {
		// If the parameter is missing, return nil
		guard self[name] != nil else {
			return nil
		}
		
		// Use the throwing version with try? to handle any conversion errors
		return try extractParameter(named: name) as T
	}
    
    /// Extracts an array of elements of the specified type from the dictionary
    /// - Parameters:
    ///   - name: The name of the parameter
    ///   - elementType: The type of the elements in the array
    /// - Returns: The extracted array of elements
    /// - Throws: MCPToolError.invalidArgumentType if the parameter cannot be converted to an array of the specified type
    func extractArray<T>(named name: String, elementType: T.Type) throws -> [T] {
        guard let anyValue = self[name] else {
            preconditionFailure("Failed to retrieve value for parameter \(name)")
        }
        
        // Try direct type casting
        if let array = anyValue as? [T] {
            return array
        } else if let caseIterableType = elementType as? any CaseIterable.Type {
            // Handle arrays of CaseIterable enums like Weekday
            if let stringArray = anyValue as? [String] {
                return try stringArray.map { stringValue in
                    let caseLabels = caseIterableType.caseLabels
                    
                    guard let index = caseLabels.firstIndex(of: stringValue) else {
                        throw MCPToolError.invalidEnumValue(
                            parameterName: name,
                            expectedValues: caseLabels,
                            actualValue: stringValue
                        )
                    }
                    
                    guard let allCases = caseIterableType.allCases as? [T] else {
                        // This can never happen because the result of CaseIterable is an array of the enum type
                        preconditionFailure()
                    }
                    
                    // Return the actual enum case value that matches the string label
                    return allCases[index]
                }
            } else {
                throw MCPToolError.invalidArgumentType(
                    parameterName: name,
                    expectedType: "Array of Strings",
                    actualType: String(describing: Swift.type(of: anyValue))
                )
            }
        } else if let dictArray = anyValue as? [[String: Any]] {
            // For JSON-decodable types, we need to use a generic helper
            if let decodableType = elementType as? (any Decodable.Type) {
                // Convert array of dictionaries to array of the specified type using JSONSerialization
                let decoder = JSONDecoder()
                return try dictArray.map { dict in
                    let data = try JSONSerialization.data(withJSONObject: dict)
                    // Cast the result back to T after decoding
                    if let result = try decoder.decode(decodableType, from: data) as? T {
                        return result
                    } else {
                        throw MCPToolError.invalidArgumentType(
                            parameterName: name,
                            expectedType: String(describing: T.self),
                            actualType: "Decoded object could not be cast to \(String(describing: T.self))"
                        )
                    }
                }
            } else {
                throw MCPToolError.invalidArgumentType(
                    parameterName: name,
                    expectedType: "Array of Decodable objects",
                    actualType: String(describing: Swift.type(of: anyValue))
                )
            }
        } else if let stringArray = anyValue as? [String],
                  let decodableType = elementType as? (any Decodable.Type) {
            // Handle array of JSON strings
            let decoder = JSONDecoder()
            return try stringArray.map { jsonString in
                guard let data = jsonString.data(using: .utf8) else {
                    throw MCPToolError.invalidArgumentType(
                        parameterName: name,
                        expectedType: "Valid JSON string",
                        actualType: "Invalid JSON string"
                    )
                }
                if let result = try decoder.decode(decodableType, from: data) as? T {
                    return result
                } else {
                    throw MCPToolError.invalidArgumentType(
                        parameterName: name,
                        expectedType: String(describing: T.self),
                        actualType: "Decoded object could not be cast to \(String(describing: T.self))"
                    )
                }
            }
        } else {
            throw MCPToolError.invalidArgumentType(
                parameterName: name,
                expectedType: "Array of \(String(describing: T.self))",
                actualType: String(describing: Swift.type(of: anyValue))
            )
        }
    }
    
    /// Extracts an optional array of elements of the specified type from the dictionary
    /// - Parameters:
    ///   - name: The name of the parameter
    ///   - elementType: The type of the elements in the array
    /// - Returns: The extracted array of elements, or nil if the parameter is missing
    /// - Throws: MCPToolError.invalidArgumentType if the parameter cannot be converted to an array of the specified type
    func extractOptionalArray<T>(named name: String, elementType: T.Type) throws -> [T]? {
        // If the parameter is missing, return nil
        guard self[name] != nil else {
            return nil
        }
        
        // Use the throwing version to handle any conversion errors
        return try extractArray(named: name, elementType: elementType)
    }
    
    /// Extracts an Int parameter from the dictionary
    /// - Parameter name: The name of the parameter
    /// - Returns: The extracted Int value
    /// - Throws: MCPToolError.invalidArgumentType if the parameter cannot be converted to an Int
    func extractInt(named name: String) throws -> Int {
        if let value = self[name] as? Int {
            return value
        } else if let boolValue = self[name] as? Bool {
            // JSON decoding may coerce 0/1 into Bool values, so handle those
            return boolValue ? 1 : 0
        } else if let doubleValue = self[name] as? Double {
            return Int(doubleValue)
        } else {
            throw MCPToolError.invalidArgumentType(
                parameterName: name,
                expectedType: "Int",
                actualType: String(describing: Swift.type(of: self[name] ?? "nil"))
            )
        }
    }
    
    /// Extracts a Double parameter from the dictionary
    /// - Parameter name: The name of the parameter
    /// - Returns: The extracted Double value
    /// - Throws: MCPToolError.invalidArgumentType if the parameter cannot be converted to a Double
    func extractDouble(named name: String) throws -> Double {
        if let value = self[name] as? Double {
            return value
        } else if let intValue = self[name] as? Int {
            return Double(intValue)
        } else {
            throw MCPToolError.invalidArgumentType(
                parameterName: name,
                expectedType: "Double",
                actualType: String(describing: Swift.type(of: self[name] ?? "nil"))
            )
        }
    }
    
    /// Extracts a Float parameter from the dictionary
    /// - Parameter name: The name of the parameter
    /// - Returns: The extracted Float value
    /// - Throws: MCPToolError.invalidArgumentType if the parameter cannot be converted to a Float
    func extractFloat(named name: String) throws -> Float {
        if let value = self[name] as? Float {
            return value
        } else if let intValue = self[name] as? Int {
            return Float(intValue)
        } else if let doubleValue = self[name] as? Double {
            return Float(doubleValue)
        } else {
            throw MCPToolError.invalidArgumentType(
                parameterName: name,
                expectedType: "Float",
                actualType: String(describing: Swift.type(of: self[name] ?? "nil"))
            )
        }
    }
    
    /// Extracts an array of Int values from the dictionary
    /// - Parameter name: The name of the parameter
    /// - Returns: The extracted [Int] value
    /// - Throws: MCPToolError.invalidArgumentType if the parameter cannot be converted to [Int]
    func extractIntArray(named name: String) throws -> [Int] {
        if let value = self[name] as? [Int] {
            return value
        } else if let doubleArray = self[name] as? [Double] {
            return doubleArray.map { Int($0) }
        } else if let anyArray = self[name] as? [Any] {
            return try anyArray.map { element in
                if let i = element as? Int { return i }
                if let d = element as? Double { return Int(d) }
                if let f = element as? Float { return Int(f) }
                throw MCPToolError.invalidArgumentType(
                    parameterName: name,
                    expectedType: "Int",
                    actualType: String(describing: Swift.type(of: element))
                )
            }
        } else {
            throw MCPToolError.invalidArgumentType(
                parameterName: name,
                expectedType: "[Int]",
                actualType: String(describing: Swift.type(of: self[name] ?? "nil"))
            )
        }
    }
    
    /// Extracts an array of Double values from the dictionary
    /// - Parameter name: The name of the parameter
    /// - Returns: The extracted [Double] value
    /// - Throws: MCPToolError.invalidArgumentType if the parameter cannot be converted to [Double]
    func extractDoubleArray(named name: String) throws -> [Double] {
        if let value = self[name] as? [Double] {
            return value
        } else if let intArray = self[name] as? [Int] {
            return intArray.map { Double($0) }
        } else if let anyArray = self[name] as? [Any] {
            return try anyArray.map { element in
                if let d = element as? Double { return d }
                if let i = element as? Int { return Double(i) }
                if let f = element as? Float { return Double(f) }
                throw MCPToolError.invalidArgumentType(
                    parameterName: name,
                    expectedType: "Double",
                    actualType: String(describing: Swift.type(of: element))
                )
            }
        } else {
            throw MCPToolError.invalidArgumentType(
                parameterName: name,
                expectedType: "[Double]",
                actualType: String(describing: Swift.type(of: self[name] ?? "nil"))
            )
        }
    }
    
    /// Extracts an array of Float values from the dictionary
    /// - Parameter name: The name of the parameter
    /// - Returns: The extracted [Float] value
    /// - Throws: MCPToolError.invalidArgumentType if the parameter cannot be converted to [Float]
    func extractFloatArray(named name: String) throws -> [Float] {
        if let value = self[name] as? [Float] {
            return value
        } else if let intArray = self[name] as? [Int] {
            return intArray.map { Float($0) }
        } else if let doubleArray = self[name] as? [Double] {
            return doubleArray.map { Float($0) }
        } else if let anyArray = self[name] as? [Any] {
            return try anyArray.map { element in
                if let f = element as? Float { return f }
                if let d = element as? Double { return Float(d) }
                if let i = element as? Int { return Float(i) }
                throw MCPToolError.invalidArgumentType(
                    parameterName: name,
                    expectedType: "Float",
                    actualType: String(describing: Swift.type(of: element))
                )
            }
        } else {
            throw MCPToolError.invalidArgumentType(
                parameterName: name,
                expectedType: "[Float]",
                actualType: String(describing: Swift.type(of: self[name] ?? "nil"))
            )
        }
    }
    
    /// Extracts a Date parameter from the dictionary, attempting multiple parsing strategies
    /// - Parameter name: The name of the parameter
    /// - Returns: The extracted Date value
    /// - Throws: MCPToolError.invalidArgumentType if the parameter cannot be converted to a Date
    func extractDate(named name: String) throws -> Date {
        guard let anyValue = self[name] else {
            preconditionFailure("Failed to retrieve value for parameter \(name)")
        }
        
        // If it's already a Date, return it
        if let date = anyValue as? Date {
            return date
        }
        
        // Try parsing as string
        if let stringValue = anyValue as? String {
            // Try ISO 8601 date format
            let isoFormatter = ISO8601DateFormatter()
            if let date = isoFormatter.date(from: stringValue) {
                return date
            }
            
            // Try Unix timestamp (both integer and decimal)
            if let timestampDouble = Double(stringValue) {
                return Date(timeIntervalSince1970: timestampDouble)
            }
        }
        
        // Try direct conversion from number
        if let timestampDouble = anyValue as? Double {
            return Date(timeIntervalSince1970: timestampDouble)
        }
		
        if let timestampInt = anyValue as? Int {
            return Date(timeIntervalSince1970: TimeInterval(timestampInt))
        }
        
        throw MCPToolError.invalidArgumentType(
            parameterName: name,
            expectedType: "ISO 8601 Date",
            actualType: String(describing: Swift.type(of: anyValue))
        )
    }
    
    /// Extracts a Bool parameter from the dictionary, accepting both boolean and string values
    /// - Parameter name: The name of the parameter
    /// - Returns: The extracted Bool value
    /// - Throws: MCPToolError.invalidArgumentType if the parameter cannot be converted to a Bool
    func extractBool(named name: String) throws -> Bool {
        guard let anyValue = self[name] else {
            preconditionFailure("Failed to retrieve value for parameter \(name)")
        }
        
        // If it's already a Bool, return it
        if let boolValue = anyValue as? Bool {
            return boolValue
        }
        
        // Try parsing as string
        if let stringValue = anyValue as? String {
            switch stringValue.lowercased() {
            case "true":
                return true
            case "false":
                return false
            default:
                throw MCPToolError.invalidArgumentType(
                    parameterName: name,
                    expectedType: "Bool",
                    actualType: "String"
                )
            }
        }
        
        throw MCPToolError.invalidArgumentType(
            parameterName: name,
            expectedType: "Bool",
            actualType: String(describing: Swift.type(of: anyValue))
        )
    }
    
    /// Extracts a URL parameter from the dictionary, accepting both URL objects and strings that can be parsed into URLs
    /// - Parameter name: The name of the parameter
    /// - Returns: The extracted URL value
    /// - Throws: MCPToolError.invalidArgumentType if the parameter cannot be converted to a URL
    func extractURL(named name: String) throws -> URL {
        guard let anyValue = self[name] else {
            preconditionFailure("Failed to retrieve value for parameter \(name)")
        }
        
        // If it's already a URL, return it
        if let url = anyValue as? URL {
            return url
        }
        
        // Try parsing as string
        if let stringValue = anyValue as? String {
            if let url = URL(string: stringValue) {
                return url
            }
        }
        
        throw MCPToolError.invalidArgumentType(
            parameterName: name,
            expectedType: "URL",
            actualType: String(describing: Swift.type(of: anyValue))
        )
    }
} 
