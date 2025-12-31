#if os(macOS) || os(Linux) || (os(iOS) && targetEnvironment(macCatalyst))

import Foundation

/// Manages the lifecycle of an MCP server process running via stdio.
public final actor MCPServerProcess {
    private var process: Process?
    private var inputHandle: FileHandle?
    private var outputHandle: FileHandle?
    private var errorHandle: FileHandle?
    private let lineBuffer = LineBuffer()

    /// A sequence of newline-separated strings from the process output.
    public var lines: AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            guard let outHandle = outputHandle else {
                continuation.finish(throwing: MCPServerProxyError.communicationError("No output handle available"))
                return
            }

            outHandle.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil

                    Task {
                        if let line = await self.lineBuffer.getRemaining() {
                            continuation.yield(line)
                        }
                        continuation.finish()
                    }
                    return
                }

                Task {
                    await self.lineBuffer.append(data)

                    let lines = await self.lineBuffer.processLines()
                    for line in lines {
                        continuation.yield(line)
                    }
                }
            }
        }
    }

    /// Initializes a new MCP server process with the given configuration.
    /// The command is run through `/bin/zsh -lc` to ensure a shell environment.
    /// - Parameter config: The configuration for the stdio-based MCP server.
    public init(config: MCPServerStdioConfig) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")

        let shellCommand = ([config.command] + config.args).joined(separator: " ")
        let shellArgs = ["-lc", shellCommand]
        process.arguments = shellArgs

        process.currentDirectoryURL = URL(fileURLWithPath: config.workingDirectory)
        process.environment = config.environment

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        self.process = process
        self.inputHandle = inputPipe.fileHandleForWriting
        self.outputHandle = outputPipe.fileHandleForReading
        self.errorHandle = stderrPipe.fileHandleForReading
    }

    /// Starts the MCP server process.
    public func start() async throws {
        guard let process = process else {
            throw MCPServerProxyError.communicationError("Process not initialized")
        }

        try process.run()

        if !process.isRunning {
            throw MCPServerProxyError.communicationError("MCP server process failed to start")
        }
    }

    /// Writes data to the process's standard input.
    public func write(_ data: Data) {
        inputHandle?.write(data)
    }

    /// Terminates the MCP server process.
    public func terminate() {
        process?.terminate()
        process = nil
        inputHandle = nil
        outputHandle = nil
        errorHandle = nil
    }
}

#else

import Foundation

/// Stub implementation for platforms where Process is unavailable.
public final actor MCPServerProcess {
    public init(config: MCPServerStdioConfig) {
    }

    public var lines: AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: MCPServerProxyError.unsupportedPlatform("Stdio-based MCP servers require Process support."))
        }
    }

    public func start() async throws {
        throw MCPServerProxyError.unsupportedPlatform("Stdio-based MCP servers require Process support.")
    }

    public func write(_ data: Data) {
    }

    public func terminate() {
    }
}

#endif
