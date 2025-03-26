import Foundation

// MARK: - Parameter Extraction Extensions for Dictionaries
public extension Dictionary where Key == String, Value == Sendable {
    
    /// Extracts a parameter of the specified type from the dictionary
    /// - Parameter name: The name of the parameter
    /// - Returns: The extracted value of type T
    /// - Throws: MCPToolError.invalidArgumentType if the parameter cannot be converted to type T
    func extractParameter<T>(named name: String) throws -> T {
		
		guard let anyValue = self[name] else
		{
			// this can never happen because arguments have already been enriched with default values
			preconditionFailure("Failed to retrieve value for parameter \(name)")
		}
		
        // try direct type casting
        if let value = anyValue as? T {
            return value
        }
		else if let caseType = T.self as? any CaseIterable.Type
		{
			guard let string = anyValue as? String else
			{
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
		else {
            throw MCPToolError.invalidArgumentType(
                parameterName: name,
                expectedType: String(describing: T.self),
                actualType: String(describing: Swift.type(of: anyValue))
            )
        }
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
} 
