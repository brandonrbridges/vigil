import SwiftUI

struct TerminalPlaceholderView: View {
    let server: Server
    @Environment(ConnectionManager.self) private var connectionManager
    @State private var isConnected = false

    private var isServerConnected: Bool {
        connectionManager.connectionStates[server.id] == .connected
    }

    var body: some View {
        if isConnected {
            SSHTerminalView(server: server)
                .ignoresSafeArea()
                .overlay(alignment: .topTrailing) {
                    Button {
                        isConnected = false
                    } label: {
                        Label("Disconnect", systemImage: "xmark.circle.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .padding(8)
                }
        } else {
            VStack(spacing: 16) {
                Image(systemName: "terminal")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)

                Text("SSH Terminal")
                    .font(.title2.bold())

                Text("\(server.username)@\(server.host)")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Button("Connect") {
                    isConnected = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!isServerConnected)

                if !isServerConnected {
                    Text("Waiting for server connection...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
