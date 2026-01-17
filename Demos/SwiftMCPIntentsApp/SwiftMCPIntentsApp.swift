import SwiftUI

@main
struct SwiftMCPIntentsApp: App {
    @StateObject private var serverController = ServerController()

    var body: some Scene {
        WindowGroup {
            ContentView(serverController: serverController)
                .onAppear {
                    serverController.start()
                }
        }
    }
}
