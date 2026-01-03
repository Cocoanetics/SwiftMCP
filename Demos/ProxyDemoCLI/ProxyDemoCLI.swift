import Foundation
import ArgumentParser
import SwiftMCP

@main
struct ProxyDemoCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ProxyDemoCLI",
        abstract: "Exercise the generated proxy against the SwiftMCP demo server."
    )

    @Option(name: .long, help: "SSE endpoint URL for a running demo server.")
    var sse: String?

    @Option(name: .long, help: "Shell command to launch the demo server over stdio.")
    var command: String = "swift run SwiftMCPDemo stdio"

    @Option(name: .long, help: "Working directory for the stdio command.")
    var cwd: String?

    @Option(name: .long, help: "Environment variable in KEY=VALUE format (repeatable).")
    var env: [String] = []

    func run() async throws {
        let config = try makeConfig()
        let proxy = MCPServerProxy(config: config)

        defer {
            Task {
                await proxy.disconnect()
            }
        }

        try await proxy.connect()
        let client = SwiftMCPDemoProxy(proxy: proxy)
        let runner = ProxyDemoRunner(client: client)
        await runner.runAll()
    }

    private func makeConfig() throws -> MCPServerConfig {
        if let sse {
            guard let url = URL(string: sse) else {
                throw ValidationError("Invalid --sse URL: \(sse)")
            }
            return .sse(config: MCPServerSseConfig(url: url, headers: [:]))
        }

        let environment = try parseEnvironment(env)
        let workingDirectory = cwd ?? FileManager.default.currentDirectoryPath
        let stdioConfig = MCPServerStdioConfig(
            command: command,
            args: [],
            workingDirectory: workingDirectory,
            environment: environment
        )
        return .stdio(config: stdioConfig)
    }

    private func parseEnvironment(_ values: [String]) throws -> [String: String] {
        var environment: [String: String] = [:]
        for value in values {
            guard let range = value.range(of: "=") else {
                throw ValidationError("Invalid --env '\(value)'. Use KEY=VALUE.")
            }
            let key = String(value[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            let envValue = String(value[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else {
                throw ValidationError("Invalid --env '\(value)'. Use KEY=VALUE.")
            }
            environment[key] = envValue
        }
        return environment
    }
}

struct ProxyDemoRunner {
    let client: SwiftMCPDemoProxy

    func runAll() async {
        print("Running proxy demo tools...")
        await runGetCurrentDateTime()
        await runFormatDateAsString()
        await runAdd()
        await runSubtract()
        await runTestArray()
        await runMultiply()
        await runDivide()
        await runGreet()
        await runPing()
        await runNoop()
        await runRandomFile()
        await runCountdown()
        print("Proxy demo complete.")
    }

    private func runGetCurrentDateTime() async {
        await runTool("getCurrentDateTime") {
            try await client.getCurrentDateTime()
        }
    }

    private func runFormatDateAsString() async {
        let now = Date()
        await runTool("formatDateAsString") {
            try await client.formatDateAsString(date: now)
        }
    }

    private func runAdd() async {
        await runTool("add") {
            try await client.add(a: 2, b: 3)
        }
    }

    private func runSubtract() async {
        await runTool("subtract") {
            try await client.subtract()
        }
    }

    private func runTestArray() async {
        await runTool("testArray") {
            try await client.testArray(a: [1, 2, 3, 4])
        }
    }

    private func runMultiply() async {
        await runTool("multiply") {
            try await client.multiply(a: 4, b: 5)
        }
    }

    private func runDivide() async {
        await runTool("divide") {
            try await client.divide(denominator: 2, numerator: 10)
        }
    }

    private func runGreet() async {
        await runTool("greet") {
            try await client.greet(name: "Taylor")
        }
    }

    private func runPing() async {
        await runTool("ping") {
            try await client.ping()
        }
    }

    private func runNoop() async {
        await runTool("noop") {
            try await client.noop()
        }
    }

    private func runRandomFile() async {
        do {
            let items = try await client.randomFile()
            print("[OK] randomFile: \(items.count) items")
            for item in items {
                let uri = item.uri?.absoluteString ?? "nil"
                let mimeType = item.mimeType ?? "nil"
                let text = item.text ?? "nil"
                print("  uri=\(uri) mimeType=\(mimeType) text=\(text)")
            }
        } catch {
            print("[ERR] randomFile: \(error)")
        }
    }

    private func runCountdown() async {
        await runTool("countdown") {
            try await client.countdown()
        }
    }

    private func runTool<T>(_ name: String, _ action: () async throws -> T) async {
        do {
            let result = try await action()
            print("[OK] \(name): \(result)")
        } catch {
            print("[ERR] \(name): \(error)")
        }
    }
}
