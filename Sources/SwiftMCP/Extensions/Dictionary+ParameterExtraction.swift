import Foundation

// MARK: - Dictionary to Decodable Conversion
extension Dictionary where Key == String, Value == Encodable {
    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        let data = try JSONSerialization.data(withJSONObject: self)
        return try JSONDecoder().decode(type, from: data)
    }
}

// MARK: - Array of Dictionaries to Array of Decodable Conversion
extension Array where Element == [String: Encodable] {
    func decode<T: Decodable>(_ type: T.Type) throws -> [T] {
        return try map { dict in
            let data = try JSONSerialization.data(withJSONObject: dict)
            return try JSONDecoder().decode(type, from: data)
        }
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
            if let dict = anyValue as? [String: Encodable] {
                return try dict.decode(decodableType.self) as! T
            } else if let array = anyValue as? [[String: Encodable]] {
                return try array.decode(decodableType.self) as! T
            } else {
                throw MCPToolError.invalidArgumentType(
                    parameterName: name,
                    expectedType: "Dictionary or Array of Dictionaries",
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
    
    /// Extracts an Int parameter from the dictionary
    /// - Parameter name: The name of the parameter
    /// - Returns: The extracted Int value
    /// - Throws: MCPToolError.invalidArgumentType if the parameter cannot be converted to an Int
    func extractInt(named name: String) throws -> Int {
        if let value = self[name] as? Int {
            return value
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
