import SwiftUI

struct ContentView: View {
    @ObservedObject var serverController: ServerController

    var body: some View {
        VStack(spacing: 12) {
            Text("SwiftMCP Intents Demo")
                .font(.title)
            Text("Expose AppIntents as MCP tools via AppShortcutsProvider.")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text(serverController.status)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(minWidth: 360, minHeight: 200)
    }
}
