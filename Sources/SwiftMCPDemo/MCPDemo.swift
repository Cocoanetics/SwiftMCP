import Foundation
import SwiftMCP
import os

/// A simple demonstration of the MCP (Model-Controller-Protocol) request/response handling
struct MCPDemo {
    /// Logger for MCP demo
    private static let logger = Logger(subsystem: "com.swiftmcp.demo", category: "MCPDemo")
    
    /// Run the MCP demo
    static func run() {
        // Log startup to OSLog (not to stdout)
        logger.info("MCP Demo started")
        
        // Create a Calculator instance to get its tools for function listing
        let calculator = Calculator()
        
        // **Continuous Read Loop for MCP Inspector**
        while let jsonString = readLine() {
            
			logger.debug("Read: \(jsonString, privacy: .public)")
			
			guard let jsonData = jsonString.data(using: .utf8) else {
				logger.debug("Invalid Data: \(jsonString, privacy: .public)")
				continue
			}
			
			do {
				let request = try JSONDecoder().decode(JSONRPC.Request.self, from: jsonData)
				
				logger.debug("Success parsing, method \(request.method), id \(request.id)")
				
				// Handle different method types
				switch request.method {
				case "initialize":
					// Extract protocol version from the request
					var protocolVersion = "2024-11-05" // Default
					
					if let params = request.params?.value as? [String: Any] {
						if let version = params["protocolVersion"] as? String {
							protocolVersion = version
						}
					}
					
					// Create and send response
					let response = createInitializeResponse(
						id: request.id,
						protocolVersion: protocolVersion
					)
					
					// Use a custom encoder to handle the response
					let encoder = JSONEncoder()
					let responseData = try encoder.encode(response)
					
					if let responseString = String(data: responseData, encoding: .utf8) {
						print(responseString + "\n")   // Sends response to stdout
						
						logger.debug("response: \(responseString, privacy: .public)")
					}
					
				case "list_functions":
					// Create and send response with available functions
					let response = createListFunctionsResponse(
						id: request.id,
						tools: calculator.mcpTools
					)
					
					// Use a custom encoder to handle the response
					let encoder = JSONEncoder()
					let responseData = try encoder.encode(response)
					
					if let responseString = String(data: responseData, encoding: .utf8) {
						print(responseString)   // Sends response to stdout
						fflush(stdout)      // Ensures immediate output
						
						logger.debug("response: \(responseString, privacy: .public)")
					}
					
				default:
					// Method not supported
					let errorResponse = createErrorResponse(
						id: request.id,
						code: JSONRPC.ErrorCode.methodNotFound,
						message: "Method not supported: \(request.method)"
					)
					
					// Use a custom encoder to handle the response
					let encoder = JSONEncoder()
					let responseData = try encoder.encode(errorResponse)
					
					if let responseString = String(data: responseData, encoding: .utf8) {
						print(responseString)   // Sends response to stdout
						fflush(stdout)      // Ensures immediate output
						
						logger.debug("error response: \(responseString, privacy: .public)")
					}
				}
			}
			catch let error
			{
				logger.debug("Parse error: \(error.localizedDescription, privacy: .public)")
			}
        }
        
        logger.info("End of input, keeping process running")
        
        // **Keep Process Running to Maintain Connection**
        RunLoop.main.run()
    }
    
    /// Create a JSON-RPC 2.0 response for the initialize method
    private static func createInitializeResponse(
        id: JSONRPC.RequestID,
        protocolVersion: String
    ) -> JSONRPC.Response {
        // Create the server capabilities
        let capabilities: [String: Any] = [
            "tools": [
                "listChanged": true
            ],
            "prompts": [
                "listChanged": true
            ],
            "resources": [
                "subscribe": true,
                "listChanged": true
            ],
            "logging": true
        ]
        
        // Create the server info
        let serverInfo: [String: Any] = [
            "name": "ExampleServer",
            "version": "1.0.0"
        ]
        
        // Create the result object according to the MCP protocol
        let resultDict: [String: Any] = [
            "protocolVersion": protocolVersion,
            "capabilities": capabilities,
            "serverInfo": serverInfo
        ]
        
        // Create and return the JSON-RPC 2.0 response
        return JSONRPC.Response(id: id, result: AnyCodable(resultDict))
    }
    
    /// Create a JSON-RPC 2.0 response for the list_functions method
    private static func createListFunctionsResponse(
        id: JSONRPC.RequestID,
        tools: [MCPTool]
    ) -> JSONRPC.Response {
        // Create a simplified tools representation
        var toolsArray: [[String: Any]] = []
        
        for tool in tools {
            // Create a dictionary for each tool with properties in the desired order
            var toolDict: [String: Any] = [:]
            
            // 1. Name (always first)
            toolDict["name"] = tool.name
            
            // 2. Description (if available)
            if let description = tool.description {
                toolDict["description"] = description
            }
            
            // 3. InputSchema
            let inputSchema = createInputSchemaDictionary(tool.inputSchema)
            toolDict["inputSchema"] = inputSchema
            
            toolsArray.append(toolDict)
        }
        
        // Create the result object
        let resultDict: [String: Any] = [
            "functions": toolsArray
        ]
        
        // Create and return the JSON-RPC 2.0 response
        return JSONRPC.Response(id: id, result: AnyCodable(resultDict))
    }
    
    /// Create a JSON-RPC 2.0 error response
    private static func createErrorResponse(
        id: JSONRPC.RequestID,
        code: Int,
        message: String
    ) -> JSONRPC.Response {
        // Create the error object
        let errorObject = JSONRPC.ErrorObject(code: code, message: message)
        
        // Create and return the JSON-RPC 2.0 error response
        return JSONRPC.Response(id: id, error: errorObject)
    }
    
    /// Create a dictionary for the inputSchema with properties in the desired order
    private static func createInputSchemaDictionary(_ schema: JSONSchema) -> [String: Any] {
        switch schema {
        case .object(let properties, let required, let description):
            // For object schemas, ensure "type" comes first, then "properties"
            var result: [String: Any] = [:]
            
            // 1. Type (always first)
            result["type"] = "object"
            
            // 2. Properties
            var propertiesDict: [String: Any] = [:]
            for (key, value) in properties {
                propertiesDict[key] = convertJSONSchemaToDictionary(value)
            }
            result["properties"] = propertiesDict
            
            // 3. Required (if any)
            if !required.isEmpty {
                result["required"] = required
            }
            
            // 4. Description (if any)
            if let description = description {
                result["description"] = description
            }
            
            return result
            
        default:
            // For non-object schemas, use the regular conversion
            return convertJSONSchemaToDictionary(schema)
        }
    }
    
    /// Convert a JSONSchema to a dictionary representation
    private static func convertJSONSchemaToDictionary(_ schema: JSONSchema) -> [String: Any] {
        var result: [String: Any] = [:]
        
        switch schema {
        case .string(let description):
            result["type"] = "string"
            if let description = description {
                result["description"] = description
            }
            
        case .number(let description):
            result["type"] = "number"
            if let description = description {
                result["description"] = description
            }
            
        case .boolean(let description):
            result["type"] = "boolean"
            if let description = description {
                result["description"] = description
            }
            
        case .array(let items, let description):
            result["type"] = "array"
            result["items"] = convertJSONSchemaToDictionary(items)
            if let description = description {
                result["description"] = description
            }
            
        case .object(let properties, let required, let description):
            // For object schemas, ensure "type" comes first, then "properties"
            result["type"] = "object"
            
            var propertiesDict: [String: Any] = [:]
            for (key, value) in properties {
                propertiesDict[key] = convertJSONSchemaToDictionary(value)
            }
            
            result["properties"] = propertiesDict
            
            if !required.isEmpty {
                result["required"] = required
            }
            
            if let description = description {
                result["description"] = description
            }
        }
        
        return result
    }
    
    /// Create a simplified fallback response when the full response cannot be encoded
    private static func createFallbackResponse(id: JSONRPC.RequestID) -> JSONRPC.Response {
        // Create a minimal result dictionary
        let resultDict: [String: Any] = [
            "protocolVersion": "2024-11-05",
            "capabilities": [
                "tools": ["listChanged": true],
                "logging": true
            ],
            "serverInfo": [
                "name": "ExampleServer",
                "version": "1.0.0"
            ]
        ]
        
        return JSONRPC.Response(id: id, result: AnyCodable(resultDict))
    }
}

/// A simple ordered dictionary implementation to maintain property order
struct OrderedDictionary<Key: Hashable, Value> {
    private var keys: [Key] = []
    private var dict: [Key: Value] = [:]
    
    mutating func updateValue(_ value: Value, forKey key: Key) {
        if dict[key] == nil {
            keys.append(key)
        }
        dict[key] = value
    }
    
    subscript(key: Key) -> Value? {
        get { return dict[key] }
        set {
            if let newValue = newValue {
                updateValue(newValue, forKey: key)
            } else {
                dict.removeValue(forKey: key)
                if let index = keys.firstIndex(of: key) {
                    keys.remove(at: index)
                }
            }
        }
    }
    
    func asDictionary() -> [Key: Value] {
        return dict
    }
} 
