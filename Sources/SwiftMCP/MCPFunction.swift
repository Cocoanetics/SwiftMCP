import Foundation

/// A property wrapper that marks a function as an MCP function.
/// This will be used to automatically generate JSON descriptions of the function.
@propertyWrapper
public struct MCPFunction<T> {
    public let wrappedValue: T
    private let name: String?
    private let parameterNames: [String]?
    
    public init(wrappedValue: T, name: String? = nil, parameterNames: [String]? = nil) {
        self.wrappedValue = wrappedValue
        self.name = name
        self.parameterNames = parameterNames
    }
    
    public var projectedValue: MCPFunctionMetadata {
        // Use the provided name or "unnamed" as fallback
        let functionName = name ?? "unnamed"
        let functionType = String(describing: T.self)
        
        // Parse the function type to extract parameter and return types
        let metadata = parseFunctionType(functionName: functionName, functionType: functionType)
        return metadata
    }
    
    private func parseFunctionType(functionName: String, functionType: String) -> MCPFunctionMetadata {
        // Example function type: "@Sendable (Int, Int) -> Int"
        // or "@Sendable (String) -> Void"
        
        // Remove @Sendable attribute if present
        var cleanedType = functionType
        if cleanedType.hasPrefix("@Sendable ") {
            cleanedType = String(cleanedType.dropFirst(10))
        }
        
        // Split by "->" to separate parameters and return type
        let components = cleanedType.split(separator: "->")
        
        // Extract parameters
        var parameters: [ParameterInfo] = []
        if components.count > 0 {
            let paramString = components[0].trimmingCharacters(in: .whitespacesAndNewlines)
            // Remove parentheses and split by comma
            let paramList = paramString.dropFirst().dropLast().split(separator: ",")
            
            // Create parameter info for each parameter
            for (index, param) in paramList.enumerated() {
                let paramType = param.trimmingCharacters(in: .whitespacesAndNewlines)
                let paramName = parameterNames?[safe: index] ?? "param\(index + 1)" // Use provided name or generate default
                parameters.append(ParameterInfo(name: paramName, type: paramType))
            }
        }
        
        // Extract return type
        var returnType: String? = nil
        if components.count > 1 {
            let returnTypeString = components[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if returnTypeString != "Void" && returnTypeString != "()" {
                returnType = returnTypeString
            }
        }
        
        return MCPFunctionMetadata(name: functionName, parameters: parameters, returnType: returnType)
    }
}

/// A structure to hold function metadata
public struct MCPFunctionMetadata: Sendable {
    public let name: String
    public let parameters: [ParameterInfo]
    public let returnType: String?
    
    public init(name: String, parameters: [ParameterInfo], returnType: String?) {
        self.name = name
        self.parameters = parameters
        self.returnType = returnType
    }
    
    public func toJSON() -> String {
        var json = "{"
        json += "\"name\": \"\(name)\", "
        json += "\"parameters\": ["
        
        for (index, param) in parameters.enumerated() {
            json += "{\"name\": \"\(param.name)\", \"type\": \"\(param.type)\"}"
            if index < parameters.count - 1 {
                json += ", "
            }
        }
        
        json += "], "
        
        if let returnType = returnType {
            json += "\"returnType\": \"\(returnType)\""
        } else {
            json += "\"returnType\": null"
        }
        
        json += "}"
        return json
    }
}

/// A structure to hold parameter information
public struct ParameterInfo: Sendable {
    public let name: String
    public let type: String
    
    public init(name: String, type: String) {
        self.name = name
        self.type = type
    }
}

/// A registry for MCP functions
@MainActor
public class MCPFunctionRegistry {
    public static let shared = MCPFunctionRegistry()
    
    private var functions: [MCPFunctionMetadata] = []
    
    private init() {}
    
    public func register(function: MCPFunctionMetadata) {
        functions.append(function)
    }
    
    public func getAllFunctions() -> [MCPFunctionMetadata] {
        return functions
    }
    
    public func getAllFunctionsJSON() -> String {
        var json = "[\n"
        for (index, function) in functions.enumerated() {
            json += "  " + function.toJSON()
            if index < functions.count - 1 {
                json += ","
            }
            json += "\n"
        }
        json += "]"
        return json
    }
}

/// Helper function to register a function with the MCPFunctionRegistry
@MainActor
public func registerMCPFunction(name: String, parameters: [(name: String, type: String)], returnType: String?) {
    let parameterInfos = parameters.map { ParameterInfo(name: $0.name, type: $0.type) }
    let metadata = MCPFunctionMetadata(name: name, parameters: parameterInfos, returnType: returnType)
    MCPFunctionRegistry.shared.register(function: metadata)
}

/// A macro that automatically extracts parameter information from a function declaration
@attached(peer, names: prefixed(__Register_))
public macro MCPFunction() = #externalMacro(module: "SwiftMCPMacros", type: "MCPFunctionMacro")

// Extension to safely access array elements
extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
} 
