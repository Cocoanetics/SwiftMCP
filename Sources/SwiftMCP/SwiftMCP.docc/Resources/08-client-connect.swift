import SwiftMCP

let url = URL(string: "http://localhost:8080/mcp")!
let config = MCPServerConfig.sse(config: MCPServerSseConfig(url: url))
let proxy = MCPServerProxy(config: config)
try await proxy.connect()

let client = CalculatorServer.Client(proxy: proxy)
