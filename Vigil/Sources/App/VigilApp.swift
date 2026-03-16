import SwiftUI

@main
struct VigilApp: App {
    @State private var serverManager = ServerManager()
    @State private var connectionManager = ConnectionManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(serverManager)
                .environment(connectionManager)
        }
        .windowStyle(.automatic)
        .defaultSize(width: 1200, height: 800)
    }
}
