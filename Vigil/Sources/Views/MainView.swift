import SwiftUI

struct MainView: View {
    @Environment(ServerManager.self) private var serverManager
    @Environment(ConnectionManager.self) private var connectionManager

    var body: some View {
        NavigationSplitView {
            ServerSidebar()
        } detail: {
            if let server = serverManager.selectedServer {
                ServerDetailView(server: server)
                    .id(server.id)
            } else {
                ContentUnavailableView(
                    "No Server Selected",
                    systemImage: "server.rack",
                    description: Text("Select a server from the sidebar")
                )
            }
        }
    }
}
