import Foundation
import SwiftMCP

/**
 A Calculator for simple math doing additionals, subtractions etc.
 
 Testing "quoted" stuff. And on multiple lines. 'single quotes'
 */
@MCPServer(name: "SwiftMCP Demo")
actor Calculator {
	
	// must be CaseIterable to 
	enum Options: CaseIterable, CustomStringConvertible {
		var description: String
		{
			switch self {
				case .all: return "ALL"
				case .unread: return "UNREAD"
			}
		}
		
		case all
		case unread
	}
	
	/**
	 Get reminders from the reminders app with flexible filtering options.
	 
	 - Parameters:
		- completed: If true, fetch completed reminders. If false, fetch incomplete reminders. If not specified, fetch all reminders.
		- startDate: ISO date string for the start of the date range to fetch reminders from
		- endDate: ISO date string for the end of the date range to fetch reminders from
		- listNames: Names of reminder lists to fetch from. If empty or not specified, fetches from all lists.
		- searchText: Text to search for in reminder titles
	 */
	@MCPTool
	func fetchReminders(
		completed: Bool? = nil,
		startDate: String? = nil,
		endDate: String? = nil,
		listNames: [String]? = nil,
		alarms: [Int]? = nil,
		searchText: String? = nil
	) {
		
	}
	
	/// Sends an email
	/// - Parameter subject: The subject of the email
	/// - Returns Some confirmation
	@MCPTool
	func searchEmailSubject(for subject: String = "Default", option: Options = .all) async throws -> String
	{
		switch option
		{
			case .all:
				return "Search in ALL emails, for subject \(subject)"
			case .unread:
				return "Search in UNREAD emails, for subject \(subject)"
		}
	}
	
	/**
	  Gets the current date/time on the server
	 - Returns: The current time
	 */
	@MCPTool
	func getCurrentDateTime() -> Date {
		return Date()
	}
	
	/**
	  Formats a date/time as String
	  - Parameter date: The Date to format
	  - Returns: A string with the date formatted
	 */
	@MCPTool
	func formatDateAsString(date: Date) -> String {
		
		let dateFormatter = DateFormatter()
		dateFormatter.dateStyle = .long
		dateFormatter.timeStyle = .long
		
		return dateFormatter.string(from: date)
	}
	
    /// Adds two integers and returns their sum
    /// - Parameter a: First number to add
    /// - Parameter b: Second number to add
    /// - Returns: The sum of a and b
    @MCPTool(description: "Custom description: Performs addition of two numbers")
    func add(a: Int, b: Int) -> Int {
        return a + b
    }
    
    /// Subtracts the second integer from the first and returns the difference
    /// - Parameter a: Number to subtract from
    /// - Parameter b: Number to subtract
    /// - Returns: The difference between a and b
    @MCPTool
    func subtract(a: Int = 5, b: Int = 3) -> Int {
        return a - b
    }
	
    /**
     Tests array processing
     - Parameter a: Array of integers to process
     - Returns: A string representation of the array
     */
    @MCPTool(description: "Custom description: Tests array processing")
    func testArray(a: [Int] = [1,2,3]) -> String {
        return a.map(String.init).joined(separator: ", ")
    }
    
    /**
     Multiplies two integers and returns their product
     - Parameter a: First factor
     - Parameter b: Second factor
     - Returns: The product of a and b
     */
    @MCPTool
    func multiply(a: Int, b: Int) -> Int {
        return a * b
    }
    
    /// Divides the numerator by the denominator and returns the quotient
    /// - Parameter numerator: Number to be divided
    /// - Parameter denominator: Number to divide by (defaults to 1.0)
    /// - Returns: The quotient of numerator divided by denominator
    @MCPTool
    func divide(numerator: Double, denominator: Double = 1.0) -> Double {
        return numerator / denominator
    }
    
    /// Returns a greeting message with the provided name
    /// - Parameter name: Name of the person to greet
    /// - Returns: The greeting message
	@MCPTool(description: "Shows a greeting message")
	func greet(name: String) async throws -> String {
		// Validate name length
		if name.count < 2 {
			throw DemoError.nameTooShort(name: name)
		}
		
		// Validate name contains only letters and spaces
		if !name.allSatisfy({ $0.isLetter || $0.isWhitespace }) {
			throw DemoError.invalidName(name: name)
		}
		
		return "Hello, \(name)!"
	}

	
    /** A simple ping function that returns 'pong' */
	@MCPTool
	func ping() -> String {
		return "pong"
	}
	
	/** A function to test doing nothing, not returning anything*/
	@MCPTool
	func noop() {
		
	}
    
    /// Returns an array of all MCP resources defined in this type
    var mcpResources: [MCPResource] {
        // Get the Downloads folder URL
        guard let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
			logToStderr("Could not get Downloads folder URL")
            return []
        }
        
        do {
            // List all files in the Downloads folder
            let fileURLs = try FileManager.default.contentsOfDirectory(
                at: downloadsURL,
                includingPropertiesForKeys: [.isRegularFileKey, .nameKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )
            
            // Filter to only include regular files
            let regularFileURLs = fileURLs.filter { url in
                do {
                    let resourceValues = try url.resourceValues(forKeys: [.isRegularFileKey])
                    return resourceValues.isRegularFile ?? false
                } catch {
                    return false
                }
            }
            
            // Create FileResource objects for each file
            return regularFileURLs.map { fileURL in
                // Get file attributes for description
                let fileAttributes: String
                do {
                    let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
                    let fileSize = attributes[.size] as? Int64 ?? 0
                    let modificationDate = attributes[.modificationDate] as? Date ?? Date()
                    let formatter = DateFormatter()
                    formatter.dateStyle = .medium
                    formatter.timeStyle = .short
                    fileAttributes = "Size: \(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)), Modified: \(formatter.string(from: modificationDate))"
                } catch {
                    fileAttributes = "File in Downloads folder"
                }
                
                return FileResource(
                    uri: fileURL,
                    name: fileURL.lastPathComponent,
                    description: fileAttributes
                )
            }
        } catch {

			logToStderr("Error listing files in Downloads folder: \(error.localizedDescription)")
            return []
        }
    }
    
    /// Gets a resource by URI
    /// - Parameter uri: The URI of the resource to get
    /// - Returns: The resource content, or nil if the resource doesn't exist
    /// - Throws: MCPResourceError if there's an error getting the resource
    func getResource(uri: URL) throws -> MCPResourceContent? {
        // Check if the file exists
        guard FileManager.default.fileExists(atPath: uri.path) else {
            return nil
        }
        
        // Get the resource content
        return try FileResourceContent.from(fileURL: uri)
    }
}
