import Foundation
import Dispatch

final class InProcessStdioBridge: StdioConnection, @unchecked Sendable {
    private let connection: MCPServerProcess

    private let serverInput: FileHandle
    private let serverOutput: FileHandle
    private let server: any MCPServer & Sendable
    private let session = Session(id: UUID())
    private var buffer = Data()
    private let lock = NSLock()
    private let writeQueue = DispatchQueue(label: "com.cocoanetics.SwiftMCP.Client.stdio.write")

    init(server: any MCPServer & Sendable) {
        self.server = server
        let toServer = Pipe()
        let toClient = Pipe()
        let clientInput = toServer.fileHandleForWriting
        let clientOutput = toClient.fileHandleForReading
        self.serverInput = toServer.fileHandleForReading
        self.serverOutput = toClient.fileHandleForWriting
        self.connection = MCPServerProcess(stdin: clientInput, stdout: clientOutput)
    }

    func start() async throws {
        serverInput.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }

            self.lock.lock()
            self.buffer.append(data)
            let lines = self.drainLinesLocked()
            self.lock.unlock()

            for line in lines {
                Task {
                    await self.process(lineData: line)
                }
            }
        }
    }

    func stop() async {
        serverInput.readabilityHandler = nil
        await connection.stop()
    }

    func lines() async -> AsyncThrowingStream<String, Error> {
        await connection.lines()
    }

    func write(_ data: Data) async {
        await connection.write(data)
    }

    private func drainLinesLocked() -> [Data] {
        var lines: [Data] = []
        while let range = buffer.firstRange(of: Data([0x0A])) {
            let lineData = buffer[..<range.lowerBound]
            buffer.removeSubrange(..<range.upperBound)
            if !lineData.isEmpty {
                lines.append(Data(lineData))
            }
        }
        return lines
    }

    private func process(lineData: Data) async {
        do {
            let messages = try JSONRPCMessage.decodeMessages(from: lineData)
            let responses = await session.work { _ in
                await server.processBatch(messages)
            }
            guard !responses.isEmpty else { return }

            let dataToEncode: any Encodable = responses.count == 1 ? responses[0] : responses
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601WithTimeZone
            encoder.outputFormatting = [.sortedKeys]
            var data = try encoder.encode(dataToEncode)
            data.append(0x0A)
            let payload = data

            writeQueue.async {
                self.serverOutput.write(payload)
            }
        } catch {
            return
        }
    }
}
