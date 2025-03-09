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
        
        // Create and run the MCP server
        let server = MCPServer(calculator: calculator)
        
        // Run the server asynchronously
        Task {
            await server.runForever()
        }
        
        // Keep the main thread alive
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
    static func createInputSchemaDictionary(_ schema: JSONSchema) -> [String: Any] {
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
    static func convertJSONSchemaToDictionary(_ schema: JSONSchema) -> [String: Any] {
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
}

/// MCP Server implementation using async streams for I/O operations
actor MCPServer {
    private let logger = Logger(subsystem: "com.swiftmcp.demo", category: "MCPServer")
    private let calculator: Calculator
    private let stderr = FileHandle.standardError
    
    init(calculator: Calculator) {
        self.calculator = calculator
    }
    
    /// Log a message to stderr
    private func logToStderr(_ message: String) {
        if let data = (message + "\n").data(using: .utf8) {
            stderr.write(data)
        }
    }
    
    /// Run the server forever, processing input and sending responses
    func runForever() async {
        logger.info("MCP Server started, waiting for input...")
        logToStderr("MCP Server started, waiting for input...")
        
        // Create an async stream for stdin
        let stdinStream = AsyncStream<String> { continuation in
            // Start a background task to read from stdin
            Task.detached {
                while let line = readLine() {
                    continuation.yield(line)
                }
                continuation.finish()
            }
        }
        
        // Process each line from stdin
        for await line in stdinStream {
            logger.debug("Received line: \(line, privacy: .public)")
            logToStderr("Received input: \(line)")
            
            if let message = await parseJSON(line) {
                let response = await process(message)
                await sendMessage(response)
            } else {
                logToStderr("Failed to parse JSON: \(line)")
            }
        }
        
        logger.info("Input stream ended")
        logToStderr("Input stream ended")
    }
    
    /// Parse a JSON string into a dictionary
    private func parseJSON(_ jsonString: String) async -> [String: Any]? {
        guard let jsonData = jsonString.data(using: .utf8) else {
            logger.error("Failed to convert string to data")
            logToStderr("Failed to convert string to data")
            return nil
        }
        
        do {
            guard let json = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any] else {
                logger.error("Failed to parse JSON as dictionary")
                logToStderr("Failed to parse JSON as dictionary")
                return nil
            }
            return json
        } catch {
            logger.error("JSON parsing error: \(error.localizedDescription)")
            logToStderr("JSON parsing error: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Process a message and generate a response
    private func process(_ message: [String: Any]) async -> [String: Any] {
        // Extract method and id from the message
        guard let method = message["method"] as? String else {
            logger.error("Invalid request: missing method")
            logToStderr("Invalid request: missing method")
            return [
                "jsonrpc": "2.0",
                "error": [
                    "code": JSONRPC.ErrorCode.invalidRequest,
                    "message": "Invalid request: missing method"
                ],
                "id": message["id"] ?? NSNull()
            ]
        }
        
        // Extract id (can be number or string)
        let id = message["id"]
        logToStderr("Processing method: \(method), id: \(id ?? "null")")
        
        // Handle different methods
        switch method {
        case "initialize":
            // Extract protocol version if available
            var protocolVersion = "2024-11-05" // Default
            if let params = message["params"] as? [String: Any],
               let version = params["protocolVersion"] as? String {
                protocolVersion = version
            }
            
            logToStderr("Creating initialize response with protocol version: \(protocolVersion)")
            
            // Create capabilities response with the exact format requested
            return [
                "jsonrpc": "2.0",
                "id": id ?? NSNull(),
                "result": [
                    "protocolVersion": protocolVersion,
                    "capabilities": [
                        "experimental": [String: Any](),
                        "tools": [
                            "listChanged": false
                        ]
                    ],
                    "serverInfo": [
                        "name": "mcp-time",
                        "version": "1.0.0"
                    ]
                ]
            ]
            
        case "list_functions":
            logToStderr("Creating list_functions response with \(calculator.mcpTools.count) tools")
            
            // Create a list of tools
            var toolsArray: [[String: Any]] = []
            
            for tool in calculator.mcpTools {
                // Create a dictionary for each tool
                var toolDict: [String: Any] = [
                    "name": tool.name
                ]
                
                if let description = tool.description {
                    toolDict["description"] = description
                }
                
                // Convert the input schema
                toolDict["inputSchema"] = MCPDemo.createInputSchemaDictionary(tool.inputSchema)
                
                toolsArray.append(toolDict)
            }
            
            // Return the list of functions
            return [
                "jsonrpc": "2.0",
                "id": id ?? NSNull(),
                "result": [
                    "functions": toolsArray
                ]
            ]
            
        default:
            // Method not supported
            logger.error("Method not supported: \(method)")
            logToStderr("Method not supported: \(method)")
            return [
                "jsonrpc": "2.0",
                "id": id ?? NSNull(),
                "error": [
                    "code": JSONRPC.ErrorCode.methodNotFound,
                    "message": "Method not found: \(method)"
                ]
            ]
        }
    }
    
    /// Send a message to stdout
    private func sendMessage(_ response: [String: Any]) async {
        do {
            // Convert the response to JSON data
            let jsonData = try JSONSerialization.data(withJSONObject: response, options: [])
            
            // Convert the data to a string
            guard let jsonString = String(data: jsonData, encoding: .utf8) else {
                logger.error("Failed to convert response to string")
                logToStderr("Failed to convert response to string")
                return
            }
            
            // Send the response to stdout
            print(jsonString)
            print() // Add a newline to signal the end of the message
            
            logger.debug("Sent response: \(jsonString, privacy: .public)")
            logToStderr("Sent response: \(jsonString)")
        } catch {
            logger.error("Error sending response: \(error.localizedDescription)")
            logToStderr("Error sending response: \(error.localizedDescription)")
        }
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
