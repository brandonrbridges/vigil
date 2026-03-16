import SwiftUI

struct ServerDetailView: View {
    let server: Server
    @Environment(ConnectionManager.self) private var connectionManager
    @State private var selectedTab: ServerTab = .dashboard

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Dashboard", systemImage: "gauge.with.dots.needle.67percent", value: .dashboard) {
                DashboardView(server: server)
            }

            Tab("Docker", systemImage: "shippingbox", value: .docker) {
                DockerView(server: server)
            }

            Tab("Terminal", systemImage: "terminal", value: .terminal) {
                TerminalPlaceholderView(server: server)
            }

            Tab("Files", systemImage: "folder", value: .files) {
                FilesPlaceholderView(server: server)
            }
        }
        .task(id: server.id) {
            let state = connectionManager.connectionStates[server.id]
            if state == nil || state == .disconnected {
                await connectionManager.connect(to: server)
            }
        }
    }
}

enum ServerTab: String, CaseIterable {
    case dashboard
    case docker
    case terminal
    case files
}
