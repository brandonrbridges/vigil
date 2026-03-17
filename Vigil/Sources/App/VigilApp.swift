import SwiftUI

@main
struct VigilApp: App {
    @State private var serverManager = ServerManager()
    @State private var connectionManager = ConnectionManager()
    @State private var commandHistory = CommandHistoryManager()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(serverManager)
                .environment(connectionManager)
                .environment(commandHistory)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    let servers = Array(connectionManager.connectedServers.values)
                    connectionManager.cleanupAllSocketsSync(servers: servers)
                }
        }
        .windowStyle(.automatic)
        .defaultSize(width: 1200, height: 800)
    }
}
