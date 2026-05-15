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

    @Option(name: .long, help: "Bonjour service name for TCP discovery (defaults to first _mcp._tcp service).")
    var tcpService: String?

    @Option(name: .long, help: "TCP host for direct connection.")
    var tcpHost: String?

    @Option(name: .long, help: "TCP port for direct connection.")
    var tcpPort: Int?

    @Flag(name: .long, help: "Browse Bonjour and connect to the first _mcp._tcp service (prefers proxy server name).")
    var tcpBonjour: Bool = false

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

        if let tcpHost, let tcpPort {
            guard tcpPort > 0, tcpPort < 65536 else {
                throw ValidationError("Invalid --tcp-port: \(tcpPort)")
            }
            let tcpConfig = MCPServerTcpConfig(host: tcpHost, port: UInt16(tcpPort))
            return .tcp(config: tcpConfig)
        }

        if tcpHost != nil || tcpPort != nil {
            throw ValidationError("Provide both --tcp-host and --tcp-port for direct TCP connections.")
        }

        if tcpService != nil {
            let tcpConfig = MCPServerTcpConfig(serviceName: tcpService)
            return .tcp(config: tcpConfig)
        }

        if tcpBonjour {
            let tcpConfig = MCPServerTcpConfig(serviceName: SwiftMCPDemoProxy.serverName)
            return .tcp(config: tcpConfig)
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
        await runAddHours()
        await runNormalizeURL()
        await runRoundTripUUID()
        await runRoundTripData()
        await runAdd()
        await runSubtract()
        await runTestArray()
        await runMultiply()
        await runDivide()
        await runGreet()
        await runPing()
        await runNoop()
        await runRandomImage()
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
        await runTool("formatDateAsString", args: [("date", now)]) {
            try await client.formatDateAsString(date: now)
        }
    }

    private func runAddHours() async {
        let now = Date()
        await runTool("addHours", args: [("date", now), ("hours", 6)]) {
            try await client.addHours(date: now, hours: 6)
        }
    }

    private func runNormalizeURL() async {
        let url = URL(string: "https://example.com/path/./file#section")!
        await runTool("normalizeURL", args: [("url", url)]) {
            try await client.normalizeURL(url: url)
        }
    }

    private func runRoundTripUUID() async {
        let uuid = UUID()
        await runTool("roundTripUUID", args: [("uuid", uuid)]) {
            try await client.roundTripUUID(uuid: uuid)
        }
    }

    private func runRoundTripData() async {
        let data = Data("Hello, SwiftMCP!".utf8)
        await runTool("roundTripData", args: [("data", data)]) {
            try await client.roundTripData(data: data)
        }
    }

    private func runAdd() async {
        await runTool("add", args: [("a", 2), ("b", 3)]) {
            try await client.add(a: 2, b: 3)
        }
    }

    private func runSubtract() async {
        await runTool("subtract") {
            try await client.subtract()
        }
    }

    private func runTestArray() async {
        await runTool("testArray", args: [("a", [1, 2, 3, 4])]) {
            try await client.testArray(a: [1, 2, 3, 4])
        }
    }

    private func runMultiply() async {
        await runTool("multiply", args: [("a", 4), ("b", 5)]) {
            try await client.multiply(a: 4, b: 5)
        }
    }

    private func runDivide() async {
        await runTool("divide", args: [("numerator", 10), ("denominator", 2)]) {
            try await client.divide(denominator: 2, numerator: 10)
        }
    }

    private func runGreet() async {
        await runTool("greet", args: [("name", "Taylor")]) {
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

    private func runRandomImage() async {
        await runTool("randomImage") {
            try await client.randomImage()
        }
    }

    private func runCountdown() async {
        await runTool("countdown") {
            try await client.countdown()
        }
    }

    private func runTool<T>(_ name: String, args: [(String, Any)] = [], _ action: () async throws -> T) async {
        do {
            print("")
            print("---")
            print("```")
            print(callSignature(name, args: args))
            print("```")
            print("---")
            let result = try await action()
            print("result:")
            print("```")
            print(ProxyDemoFormatter.formatValue(result))
            print("```")
        } catch {
            print("error:")
            print("```")
            print(String(describing: error))
            print("```")
        }
    }

    private func callSignature(_ name: String, args: [(String, Any)]) -> String {
        let argsDescription = args
            .map { "\($0.0)=\(ProxyDemoFormatter.formatValue($0.1))" }
            .joined(separator: ", ")
        return argsDescription.isEmpty ? "\(name)()" : "\(name)(\(argsDescription))"
    }
}
