import SwiftUI

struct ServerSidebar: View {
    enum SheetType: Identifiable {
        case add
        case edit(Server)

        var id: String {
            switch self {
            case .add: "add"
            case .edit(let server): "edit-\(server.id)"
            }
        }
    }

    @Environment(ServerManager.self) private var serverManager
    @Environment(ConnectionManager.self) private var connectionManager
    @Environment(\.openWindow) private var openWindow
    @State private var activeSheet: SheetType?
    @State private var verifiedHosts: [VerifiedHost] = []
    @State private var isProbing = false
    @State private var serverToDelete: Server?

    /// Verified hosts not already added as servers
    private var availableHosts: [VerifiedHost] {
        let existingHosts = Set(serverManager.servers.map(\.host))
        return verifiedHosts.filter { !existingHosts.contains($0.host) }
    }

    var body: some View {
        @Bindable var manager = serverManager

        List(selection: $manager.selectedServerID) {
            Section("Servers") {
                ForEach(serverManager.servers) { server in
                    ServerRow(
                        server: server,
                        state: connectionManager.connectionStates[server.id] ?? .disconnected
                    )
                    .tag(server.id)
                    .contextMenu {
                        Button("Edit Server...", systemImage: "pencil") {
                            activeSheet = .edit(server)
                        }

                        Button("Open in New Window", systemImage: "macwindow.badge.plus") {
                            openWindow(value: server.id)
                        }

                        Button("Reconnect", systemImage: "arrow.clockwise") {
                            Task {
                                await connectionManager.disconnect(from: server)
                                await connectionManager.connect(to: server)
                            }
                        }

                        Divider()

                        Button("Remove", systemImage: "trash", role: .destructive) {
                            serverToDelete = server
                        }
                    }
                }
            }

            if isProbing {
                Section("Quick Add") {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Scanning for servers...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else if !availableHosts.isEmpty {
                Section("Quick Add") {
                    ForEach(availableHosts) { host in
                        Button {
                            let server = host.toServer()
                            serverManager.addServer(server)
                            Task {
                                await connectionManager.connect(to: server)
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "plus.circle")
                                    .foregroundStyle(.green)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(host.host)
                                        .font(.headline)
                                        .lineLimit(1)
                                    Text("\(host.username)@\(host.host)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .buttonStyle(.plain)
                    .selectionDisabled()
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 200)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    activeSheet = .add
                } label: {
                    Image(systemName: "plus")
                }

            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .add:
                AddServerSheet()
            case .edit(let server):
                EditServerSheet(server: server)
            }
        }
        .alert("Remove Server?", isPresented: Binding(
            get: { serverToDelete != nil },
            set: { if !$0 { serverToDelete = nil } }
        ), presenting: serverToDelete) { server in
            Button("Remove", role: .destructive) {
                Task {
                    await connectionManager.disconnect(from: server)
                }
                serverManager.removeServer(server)
            }
            Button("Cancel", role: .cancel) {}
        } message: { server in
            Text("This will remove \(server.displayName) and its saved credentials.")
        }
        .onChange(of: serverManager.selectedServerID) { _, _ in
            serverManager.persistSelection()
        }
        .task {
            await probeHosts()
        }
        .onReceive(NotificationCenter.default.publisher(for: .addServer)) { _ in
            activeSheet = .add
        }
        .onReceive(NotificationCenter.default.publisher(for: .editServer)) { _ in
            if let id = serverManager.selectedServerID,
               let server = serverManager.servers.first(where: { $0.id == id }) {
                activeSheet = .edit(server)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .reconnectServer)) { _ in
            if let id = serverManager.selectedServerID,
               let server = serverManager.servers.first(where: { $0.id == id }) {
                Task {
                    await connectionManager.reconnect(server: server)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openServerInNewWindow)) { _ in
            if let id = serverManager.selectedServerID {
                openWindow(value: id)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .disconnectServer)) { _ in
            if let id = serverManager.selectedServerID,
               let server = serverManager.servers.first(where: { $0.id == id }) {
                Task {
                    await connectionManager.disconnect(from: server)
                }
            }
        }
    }

    private func probeHosts() async {
        isProbing = true

        // Get candidate hosts from known_hosts and ssh config
        let entries = SSHConfigParser.parse()
        let existingHosts = Set(serverManager.servers.map(\.host))
        let candidates = entries
            .filter { !existingHosts.contains($0.hostname) }
            .map { ($0.hostname, $0.port) }

        guard !candidates.isEmpty else {
            isProbing = false
            return
        }

        let prober = SSHProber()
        let results = await prober.probe(hosts: candidates)

        verifiedHosts = results
        isProbing = false
    }
}

struct ServerRow: View {
    let server: Server
    let state: ConnectionManager.ConnectionState

    private var statusColor: Color {
        switch state {
        case .connected: .green
        case .connecting: .orange
        case .failed: .red
        case .disconnected: .gray
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .accessibilityLabel("Connection status: \(state == .connected ? "connected" : state == .connecting ? "connecting" : state == .disconnected ? "disconnected" : "failed")")

            VStack(alignment: .leading, spacing: 2) {
                Text(server.displayName)
                    .font(.headline)
                    .lineLimit(1)

                Text("\(server.username)@\(server.host)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}
