import Foundation

// MARK: - Parameter Extraction Extensions
public extension MCPToolParameterInfo {
	
	/// Extracts a Double parameter from a dictionary
	/// - Parameters:
	///   - name: The name of the parameter
	///   - params: The dictionary containing parameters
	///   - defaultValue: An optional default value to use if the parameter is not found
	/// - Returns: The extracted Double value
	/// - Throws: MCPToolError.invalidArgumentType if the parameter cannot be converted to a Double
	static func extractDoubleParameter(named name: String, from params: [String: Sendable], defaultValue: Double? = nil) throws -> Double {
		if let value = params[name] as? Double {
			return value
		} else if let intValue = params[name] as? Int {
			return Double(intValue)
		} else if let defaultValue = defaultValue {
			return defaultValue
		} else {
			throw MCPToolError.invalidArgumentType(
				parameterName: name,
				expectedType: "Double",
				actualType: String(describing: Swift.type(of: params[name] ?? "nil"))
			)
		}
	}
	
	/// Extracts a Float parameter from a dictionary
	/// - Parameters:
	///   - name: The name of the parameter
	///   - params: The dictionary containing parameters
	///   - defaultValue: An optional default value to use if the parameter is not found
	/// - Returns: The extracted Float value
	/// - Throws: MCPToolError.invalidArgumentType if the parameter cannot be converted to a Float
	static func extractFloatParameter(named name: String, from params: [String: Sendable], defaultValue: Float? = nil) throws -> Float {
		if let value = params[name] as? Float {
			return value
		} else if let intValue = params[name] as? Int {
			return Float(intValue)
		} else if let doubleValue = params[name] as? Double {
			return Float(doubleValue)
		} else if let defaultValue = defaultValue {
			return defaultValue
		} else {
			throw MCPToolError.invalidArgumentType(
				parameterName: name,
				expectedType: "Float",
				actualType: String(describing: Swift.type(of: params[name] ?? "nil"))
			)
		}
	}
	
	/// Extracts an Int parameter from a dictionary
	/// - Parameters:
	///   - name: The name of the parameter
	///   - params: The dictionary containing parameters
	///   - defaultValue: An optional default value to use if the parameter is not found
	/// - Returns: The extracted Int value
	/// - Throws: MCPToolError.invalidArgumentType if the parameter cannot be converted to an Int
	static func extractIntParameter(named name: String, from params: [String: Sendable], defaultValue: Int? = nil) throws -> Int {
		if let value = params[name] as? Int {
			return value
		} else if let doubleValue = params[name] as? Double {
			return Int(doubleValue)
		} else if let defaultValue = defaultValue {
			return defaultValue
		} else {
			throw MCPToolError.invalidArgumentType(
				parameterName: name,
				expectedType: "Int",
				actualType: String(describing: Swift.type(of: params[name] ?? "nil"))
			)
		}
	}
	
	/// Extracts an array of Int parameters from a dictionary
	/// - Parameters:
	///   - name: The name of the parameter
	///   - params: The dictionary containing parameters
	///   - defaultValue: An optional default value to use if the parameter is not found
	/// - Returns: The extracted [Int] value
	/// - Throws: MCPToolError.invalidArgumentType if the parameter cannot be converted to [Int]
	static func extractIntArrayParameter(named name: String, from params: [String: Sendable], defaultValue: [Int]? = nil) throws -> [Int] {
		if let value = params[name] as? [Int] {
			return value
		} else if let doubleArray = params[name] as? [Double] {
			return doubleArray.map { Int($0) }
		} else if let defaultValue = defaultValue {
			return defaultValue
		} else {
			throw MCPToolError.invalidArgumentType(
				parameterName: name,
				expectedType: "[Int]",
				actualType: String(describing: Swift.type(of: params[name] ?? "nil"))
			)
		}
	}
	
	/// Extracts an array of Double parameters from a dictionary
	/// - Parameters:
	///   - name: The name of the parameter
	///   - params: The dictionary containing parameters
	///   - defaultValue: An optional default value to use if the parameter is not found
	/// - Returns: The extracted [Double] value
	/// - Throws: MCPToolError.invalidArgumentType if the parameter cannot be converted to [Double]
	static func extractDoubleArrayParameter(named name: String, from params: [String: Sendable], defaultValue: [Double]? = nil) throws -> [Double] {
		if let value = params[name] as? [Double] {
			return value
		} else if let intArray = params[name] as? [Int] {
			return intArray.map { Double($0) }
		} else if let defaultValue = defaultValue {
			return defaultValue
		} else {
			throw MCPToolError.invalidArgumentType(
				parameterName: name,
				expectedType: "[Double]",
				actualType: String(describing: Swift.type(of: params[name] ?? "nil"))
			)
		}
	}
	
	/// Extracts an array of Float parameters from a dictionary
	/// - Parameters:
	///   - name: The name of the parameter
	///   - params: The dictionary containing parameters
	///   - defaultValue: An optional default value to use if the parameter is not found
	/// - Returns: The extracted [Float] value
	/// - Throws: MCPToolError.invalidArgumentType if the parameter cannot be converted to [Float]
	static func extractFloatArrayParameter(named name: String, from params: [String: Sendable], defaultValue: [Float]? = nil) throws -> [Float] {
		if let value = params[name] as? [Float] {
			return value
		} else if let intArray = params[name] as? [Int] {
			return intArray.map { Float($0) }
		} else if let doubleArray = params[name] as? [Double] {
			return doubleArray.map { Float($0) }
		} else if let defaultValue = defaultValue {
			return defaultValue
		} else {
			throw MCPToolError.invalidArgumentType(
				parameterName: name,
				expectedType: "[Float]",
				actualType: String(describing: Swift.type(of: params[name] ?? "nil"))
			)
		}
	}
	
	/// Extracts a parameter of the specified type from a dictionary
	/// - Parameters:
	///   - name: The name of the parameter
	///   - params: The dictionary containing parameters
	///   - defaultValue: An optional default value to use if the parameter is not found
	/// - Returns: The extracted value of type T
	/// - Throws: MCPToolError.invalidArgumentType if the parameter cannot be converted to type T
	static func extractParameter<T>(named name: String, from params: [String: Sendable], defaultValue: T? = nil) throws -> T {
		if let value = params[name] as? T {
			return value
		} else if let defaultValue = defaultValue {
			return defaultValue
		} else {
			throw MCPToolError.invalidArgumentType(
				parameterName: name,
				expectedType: String(describing: T.self),
				actualType: String(describing: Swift.type(of: params[name] ?? "nil"))
			)
		}
	}
}
