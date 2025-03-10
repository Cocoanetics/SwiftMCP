import Foundation
import ArgumentParser
import SwiftMCP
import AnyCodable

/// Command-line interface for the SwiftMCP demo
@main
struct MCPCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "mcp",
        abstract: "A utility for testing SwiftMCP functions",
        discussion: """
        Process JSON-RPC requests for SwiftMCP functions.
        
        You can pipe a JSON-RPC request to the command:
        echo '{"jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": {"name": "divide", "arguments": {"numerator": "10"}}}' | mcp
        
        Or use the interactive mode to process multiple requests:
        mcp --interactive
        
        Or use the continuous mode to run indefinitely:
        mcp --continuous
        """
    )
    
    /// Whether to run in interactive mode (waiting for input until EOF)
    @Flag(name: .long, help: "Run in interactive mode, processing multiple requests until EOF")
    var interactive = false
    
    /// Whether to run in continuous mode (never exiting, waiting for input indefinitely)
    @Flag(name: .long, help: "Run in continuous mode, processing requests indefinitely without exiting")
    var continuous = false
    
    /// The input file to read from (defaults to stdin)
    @Option(name: .shortAndLong, help: "The input file to read from (defaults to stdin)")
    var inputFile: String?
    
    /// The output file to write to (defaults to stdout)
    @Option(name: .shortAndLong, help: "The output file to write to (defaults to stdout)")
    var outputFile: String?
    
    /// Whether to enable verbose logging
    @Flag(name: .shortAndLong, help: "Enable verbose logging")
    var verbose = false
    
    /// The main entry point for the command
    func run() throws {
        // Create an instance of the Calculator
        let calculator = Calculator()
		
		if verbose {
            print(calculator.mcpTools)
        }
        
        // Set up input and output
        let inputStream: InputStream
        let outputStream: OutputStream
        
        if let inputFile = inputFile {
            guard let stream = InputStream(fileAtPath: inputFile) else {
                throw ValidationError("Could not open input file: \(inputFile)")
            }
            inputStream = stream
        } else {
            inputStream = InputStream(fileAtPath: "/dev/stdin")!
        }
        
        if let outputFile = outputFile {
            guard let stream = OutputStream(toFileAtPath: outputFile, append: false) else {
                throw ValidationError("Could not open output file: \(outputFile)")
            }
            outputStream = stream
        } else {
            outputStream = OutputStream(toFileAtPath: "/dev/stdout", append: true)!
        }
        
        // Open the streams
        inputStream.open()
        outputStream.open()
        
        // Process input
        if continuous {
            // Continuous mode: process requests indefinitely
            processContinuousInput(inputStream: inputStream, outputStream: outputStream, server: calculator)
        } else if interactive {
            // Interactive mode: process multiple requests until EOF
            processInteractiveInput(inputStream: inputStream, outputStream: outputStream, server: calculator)
        } else {
            // One-off mode: process a single request and exit
            processOneOffInput(inputStream: inputStream, outputStream: outputStream, server: calculator)
        }
        
        // Close the streams
        inputStream.close()
        outputStream.close()
    }
    
    /// Process input in continuous mode (never exiting, waiting for input indefinitely)
    private func processContinuousInput(inputStream: InputStream, outputStream: OutputStream, server: MCPServer) {
        if verbose {
            logToStderr("Starting continuous mode...")
            
            // Print available tools
            logToStderr("Available tools:")
            for tool in server.mcpTools {
                logToStderr("Tool: \(tool.name)")
                logToStderr("  Description: \(tool.description ?? "No description")")
                logToStderr("  Input Schema: \(tool.inputSchema)")
                
                if case .object(let properties, let required, _) = tool.inputSchema {
                    logToStderr("  Properties:")
                    for (key, value) in properties {
                        logToStderr("    \(key): \(value)")
                    }
                    logToStderr("  Required: \(required)")
                }
            }
        }
        
        // Continue processing inputs indefinitely
        while true {
            if let input = readLine(from: inputStream), let data = input.data(using: .utf8) {
                // Log the input for debugging
                if verbose {
                    logToStderr("Received input: \(input)")
                }
                
                processJSONRPCRequest(data: data, outputStream: outputStream, server: server)
            } else {
                // If readLine() returns nil, sleep briefly and continue
                Thread.sleep(forTimeInterval: 0.1)
            }
        }
    }
    
    /// Read a line from stdin in continuous mode, never returning nil on EOF
    private func readLineFromStdinContinuous() -> String? {
        // This method is no longer used, we're using readLine(from:) instead
        return nil
    }
    
    /// Process input in interactive mode (waiting for input until EOF)
    private func processInteractiveInput(inputStream: InputStream, outputStream: OutputStream, server: MCPServer) {
        // Continue processing inputs
        while true {
            if let input = readLine(from: inputStream), let data = input.data(using: .utf8) {
                // Log the input for debugging
                if verbose {
                    logToStderr("Received input: \(input)")
                }
                
                processJSONRPCRequest(data: data, outputStream: outputStream, server: server)
            } else {
                // If readLine() returns nil (EOF), exit
                break
            }
        }
    }
    
    /// Process input in one-off mode (process a single request and exit)
    private func processOneOffInput(inputStream: InputStream, outputStream: OutputStream, server: MCPServer) {
        // Read all input data
        var buffer = [UInt8](repeating: 0, count: 1024)
        var inputData = Data()
        
        while inputStream.hasBytesAvailable {
            let bytesRead = inputStream.read(&buffer, maxLength: buffer.count)
            if bytesRead > 0 {
                inputData.append(buffer, count: bytesRead)
            } else {
                break
            }
        }
        
        // Convert to string
        guard let input = String(data: inputData, encoding: .utf8) else {
            logToStderr("Failed to decode input as UTF-8")
            return
        }
        
        // Log the input for debugging
        if verbose {
            logToStderr("Received input: \(input)")
        }
        
        // Process each line as a separate JSON-RPC request
        let lines = input.components(separatedBy: .newlines).filter { !$0.isEmpty }
        
        if lines.count > 1 {
            // Multiple lines - process each one
            for line in lines {
                if let data = line.data(using: .utf8) {
                    processJSONRPCRequest(data: data, outputStream: outputStream, server: server)
                }
            }
        } else {
            // Single request - process it directly
            processJSONRPCRequest(data: inputData, outputStream: outputStream, server: server)
        }
    }
    
    /// Process a JSON-RPC request
    private func processJSONRPCRequest(data: Data, outputStream: OutputStream, server: MCPServer) {
        do {
            // Try to decode the JSON-RPC request
            let request = try JSONDecoder().decode(SwiftMCP.JSONRPCRequest.self, from: data)
            
            // Handle the request
            if let response = server.handleRequest(request) {
                write(response, to: outputStream)
                write("\n", to: outputStream)
            }
        } catch {
            server.logToStderr("Failed to decode JSON-RPC request: \(error)")
        }
    }
    
    /// Read a line from an input stream
    private func readLine(from inputStream: InputStream) -> String? {
        var buffer = [UInt8](repeating: 0, count: 1024)
        var line = ""
        
        while inputStream.hasBytesAvailable {
            let bytesRead = inputStream.read(&buffer, maxLength: buffer.count)
            if bytesRead > 0 {
                if let chunk = String(bytes: buffer[0..<bytesRead], encoding: .utf8) {
                    line += chunk
                    if line.contains("\n") {
                        let components = line.components(separatedBy: "\n")
                        if components.count > 1 {
                            return components[0]
                        }
                    }
                }
            } else {
                break
            }
        }
        
        return line.isEmpty ? nil : line
    }
    
    /// Write a string to an output stream
    private func write(_ string: String, to outputStream: OutputStream) {
        if let data = string.data(using: .utf8) {
            _ = data.withUnsafeBytes { outputStream.write($0.bindMemory(to: UInt8.self).baseAddress!, maxLength: data.count) }
        }
    }
    
    /// Log a message to stderr
    private func logToStderr(_ message: String) {
        fputs("\(message)\n", stderr)
    }
} 
