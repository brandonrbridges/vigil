import SwiftUI

@main
struct VigilApp: App {
    @State private var serverManager = ServerManager.shared
    @State private var connectionManager = ConnectionManager.shared
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

        WindowGroup("Server", for: UUID.self) { $serverID in
            if let serverID, let server = serverManager.servers.first(where: { $0.id == serverID }) {
                ServerDetailView(server: server)
                    .environment(connectionManager)
                    .environment(commandHistory)
                    .environment(appSettings)
            }
        }
        .defaultSize(width: 900, height: 700)
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

                Button("Open in New Window") {
                    NotificationCenter.default.post(name: .openServerInNewWindow, object: nil)
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
                .environment(appSettings)
        }
    }

    init() {}
}
