import SwiftUI

@main
struct VigilApp: App {
    @State private var serverManager = ServerManager()
    @State private var connectionManager = ConnectionManager()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(serverManager)
                .environment(connectionManager)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    Task { @MainActor in
                        await connectionManager.disconnectAll()
                    }
                }
        }
        .windowStyle(.automatic)
        .defaultSize(width: 1200, height: 800)
    }
}
