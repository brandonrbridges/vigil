import SwiftUI

@main
struct VigilApp: App {
    @State private var serverManager = ServerManager()
    @State private var connectionManager = ConnectionManager()
    @State private var commandHistory = CommandHistoryManager()
    @State private var appSettings = AppSettings()
    @State private var statusBar: StatusBarManager?
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(serverManager)
                .environment(connectionManager)
                .environment(commandHistory)
                .environment(appSettings)
                .task {
                    connectionManager.configure(settings: appSettings)
                    connectionManager.notificationService?.requestPermission()
                    statusBar = StatusBarManager(
                        serverManager: serverManager,
                        connectionManager: connectionManager
                    )
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    let servers = Array(connectionManager.connectedServers.values)
                    connectionManager.cleanupAllSocketsSync(servers: servers)
                }
        }
        .windowStyle(.automatic)
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add Server...") {
                    NotificationCenter.default.post(name: .addServer, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }

            CommandMenu("Server") {
                Button("Reconnect") {
                    NotificationCenter.default.post(name: .reconnectServer, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                Button("Disconnect") {
                    NotificationCenter.default.post(name: .disconnectServer, object: nil)
                }

                Divider()

                Button("Edit Server...") {
                    NotificationCenter.default.post(name: .editServer, object: nil)
                }
                .keyboardShortcut("e", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .environment(appSettings)
        }
    }

    init() {}
}
