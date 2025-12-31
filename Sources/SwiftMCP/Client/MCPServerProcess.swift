#if os(macOS) || os(Linux) || (os(iOS) && targetEnvironment(macCatalyst))

import Foundation

/// Manages a stdio connection to an MCP server, optionally backed by a process.
public final actor MCPServerProcess: StdioConnection {
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

    /// Initializes a new stdio connection using the provided handles.
    public init(stdin: FileHandle, stdout: FileHandle) {
        self.process = nil
        self.inputHandle = stdin
        self.outputHandle = stdout
        self.errorHandle = nil
    }

    /// Starts the MCP server process (no-op for handle-based connections).
    public func start() async throws {
        guard let process = process else { return }

        try process.run()

        if !process.isRunning {
            throw MCPServerProxyError.communicationError("MCP server process failed to start")
        }
    }

    /// Writes data to the process's standard input.
    private func writeSync(_ data: Data) {
        inputHandle?.write(data)
    }

    /// Terminates the MCP server process or detaches stdio handles.
    public func terminate() {
        outputHandle?.readabilityHandler = nil
        process?.terminate()
        process = nil
        inputHandle = nil
        outputHandle = nil
        errorHandle = nil
    }

    public func write(_ data: Data) async {
        writeSync(data)
    }

    public func stop() async {
        terminate()
    }

    public func lines() async -> AsyncThrowingStream<String, Error> {
        lines
    }
}

#else

import Foundation

/// Stub implementation for platforms where Process is unavailable.
public final actor MCPServerProcess: StdioConnection {
    public init(config: MCPServerStdioConfig) {
    }

    public init(stdin: FileHandle, stdout: FileHandle) {
    }

    public var lines: AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: MCPServerProxyError.unsupportedPlatform("Stdio-based MCP servers require Process support."))
        }
    }

    public func start() async throws {
        throw MCPServerProxyError.unsupportedPlatform("Stdio-based MCP servers require Process support.")
    }

    public func terminate() {
    }

    public func write(_ data: Data) async {
    }

    public func stop() async {
    }

    public func lines() async -> AsyncThrowingStream<String, Error> {
        lines
    }
}

#endif
