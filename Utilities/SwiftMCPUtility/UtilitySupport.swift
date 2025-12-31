import Foundation
import ArgumentParser
import SwiftMCP

struct ConnectionOptions: ParsableArguments {
    @Option(name: .long, help: "Path to JSON config file for the connection")
    var config: String?

    @Option(name: .long, help: "SSE endpoint URL, e.g. http://localhost:8080/sse")
    var sse: String?

    @Option(name: .long, help: "HTTP header in Key:Value or Key=Value format (repeatable)")
    var header: [String] = []

    @Option(name: .long, help: "Command line for stdio connection (quote if it contains spaces)")
    var command: String?

    @Option(name: .long, help: "Working directory for stdio connection")
    var cwd: String?

    @Option(name: .long, help: "Environment variable in KEY=VALUE format (repeatable)")
    var env: [String] = []
}

enum UtilitySupport {
    static func makeConfig(from options: ConnectionOptions) throws -> MCPServerConfig {
        if let configPath = options.config {
            if options.sse != nil || options.command != nil || !options.header.isEmpty || options.cwd != nil || !options.env.isEmpty {
                throw ValidationError("Use --config by itself; do not combine it with --sse, --command, --header, --cwd, or --env.")
            }
            let config = try loadConfig(from: configPath)
            return try makeConfig(from: config)
        }

        let hasSse = options.sse != nil
        let hasCommand = options.command != nil
        if hasSse == hasCommand {
            throw ValidationError("Specify exactly one connection: either --sse or --command.")
        }

        if let sse = options.sse {
            guard let url = URL(string: sse) else {
                throw ValidationError("Invalid --sse URL: \(sse)")
            }
            let headers = try parseHeaders(options.header)
            return .sse(config: MCPServerSseConfig(url: url, headers: headers))
        }

        guard let commandLine = options.command else {
            throw ValidationError("Missing --command for stdio connection.")
        }

        let tokens = try splitCommandLine(commandLine)
        guard let command = tokens.first else {
            throw ValidationError("The --command value is empty.")
        }

        let workingDirectory = options.cwd ?? FileManager.default.currentDirectoryPath
        let environment = try parseEnvironment(options.env)
        let stdioConfig = MCPServerStdioConfig(
            command: command,
            args: Array(tokens.dropFirst()),
            workingDirectory: workingDirectory,
            environment: environment
        )
        return .stdio(config: stdioConfig)
    }

    private static func makeConfig(from config: UtilityConfig) throws -> MCPServerConfig {
        let hasSse = config.sse != nil
        let hasCommand = config.command != nil
        if hasSse == hasCommand {
            throw ValidationError("Config must specify exactly one connection: either 'sse' or 'command'.")
        }

        if let sse = config.sse {
            guard let url = URL(string: sse) else {
                throw ValidationError("Invalid 'sse' URL in config: \(sse)")
            }
            let headers = config.headers ?? [:]
            return .sse(config: MCPServerSseConfig(url: url, headers: headers))
        }

        guard let commandLine = config.command else {
            throw ValidationError("Config is missing 'command' for stdio connection.")
        }
        let tokens = try splitCommandLine(commandLine)
        guard let command = tokens.first else {
            throw ValidationError("The 'command' value in config is empty.")
        }

        let workingDirectory = config.cwd ?? FileManager.default.currentDirectoryPath
        let environment = config.env ?? [:]
        let stdioConfig = MCPServerStdioConfig(
            command: command,
            args: Array(tokens.dropFirst()),
            workingDirectory: workingDirectory,
            environment: environment
        )
        return .stdio(config: stdioConfig)
    }

    private static func loadConfig(from path: String) throws -> UtilityConfig {
        let url = URL(fileURLWithPath: path)
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ValidationError("Failed to read config file: \(error.localizedDescription)")
        }
        do {
            return try JSONDecoder().decode(UtilityConfig.self, from: data)
        } catch {
            throw ValidationError("Failed to parse config JSON: \(error.localizedDescription)")
        }
    }

    static func writeOutput(_ text: String, to output: String?) throws {
        if let output {
            let url = URL(fileURLWithPath: output)
            guard let data = text.data(using: .utf8) else {
                throw ValidationError("Failed to encode output as UTF-8.")
            }
            try data.write(to: url, options: .atomic)
        } else {
            print(text)
        }
    }

    static func parseHeaders(_ values: [String]) throws -> [String: String] {
        var headers: [String: String] = [:]
        for value in values {
            guard let (key, headerValue) = splitKeyValue(value, separators: [":", "="]) else {
                throw ValidationError("Invalid header '\(value)'. Use Key:Value or Key=Value.")
            }
            headers[key] = headerValue
        }
        return headers
    }

    static func parseEnvironment(_ values: [String]) throws -> [String: String] {
        var environment: [String: String] = [:]
        for value in values {
            guard let (key, envValue) = splitKeyValue(value, separators: ["="]) else {
                throw ValidationError("Invalid environment variable '\(value)'. Use KEY=VALUE.")
            }
            environment[key] = envValue
        }
        return environment
    }

    static func splitKeyValue(_ value: String, separators: [String]) -> (String, String)? {
        for separator in separators {
            if let range = value.range(of: separator) {
                let key = String(value[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                let val = String(value[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                if !key.isEmpty {
                    return (key, val)
                }
            }
        }
        return nil
    }

    static func splitCommandLine(_ commandLine: String) throws -> [String] {
        var tokens: [String] = []
        var current = ""
        var inSingleQuote = false
        var inDoubleQuote = false
        var escapeNext = false

        for scalar in commandLine.unicodeScalars {
            let character = Character(scalar)
            if escapeNext {
                current.append(character)
                escapeNext = false
                continue
            }

            switch character {
                case "\\":
                    escapeNext = true
                case "\"":
                    if !inSingleQuote {
                        inDoubleQuote.toggle()
                    } else {
                        current.append(character)
                    }
                case "'":
                    if !inDoubleQuote {
                        inSingleQuote.toggle()
                    } else {
                        current.append(character)
                    }
                case " ", "\t", "\n":
                    if inSingleQuote || inDoubleQuote {
                        current.append(character)
                    } else if !current.isEmpty {
                        tokens.append(current)
                        current = ""
                    }
                default:
                    current.append(character)
            }
        }

        if escapeNext {
            current.append("\\")
        }

        if inSingleQuote || inDoubleQuote {
            throw ValidationError("Unterminated quote in --command.")
        }

        if !current.isEmpty {
            tokens.append(current)
        }

        return tokens
    }
}

private struct UtilityConfig: Codable {
    let sse: String?
    let headers: [String: String]?
    let command: String?
    let cwd: String?
    let env: [String: String]?
}
