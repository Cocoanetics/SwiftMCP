import Foundation

/// Actor to handle stdout and stderr access safely using FileHandle.
public actor AsyncOutput {
    public static let shared = AsyncOutput()
    
    private init() {}
    
    public func writeToStdout(_ message: String) async throws {
        guard let data = (message + "\n").data(using: .utf8) else { return }
        try FileHandle.standardOutput.write(contentsOf: data)
    }
    
    public func writeToStderr(_ message: String) async throws {
        guard let data = (message + "\n").data(using: .utf8) else { return }
        try FileHandle.standardError.write(contentsOf: data)
    }
} 