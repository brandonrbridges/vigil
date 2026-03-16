import SwiftUI

struct TerminalPlaceholderView: View {
    let server: Server
    @Environment(ConnectionManager.self) private var connectionManager
    @Environment(CommandHistoryManager.self) private var commandHistory
    @State private var isConnected = false
    @State private var terminalFD: Int32 = -1
    @State private var showHistorySidebar = false
    @State private var showQuickInsertAlert = false
    @State private var pendingInsertCommand: String?

    private var isServerConnected: Bool {
        connectionManager.connectionStates[server.id] == .connected
    }

    var body: some View {
        if isConnected {
            SSHTerminalView(server: server, masterFileDescriptor: $terminalFD)
                .background(.ultraThinMaterial)
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
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showHistorySidebar.toggle()
                        } label: {
                            Label("Command History", systemImage: "sidebar.right")
                        }
                        .keyboardShortcut("h", modifiers: [.command, .shift])
                    }
                }
                .inspector(isPresented: $showHistorySidebar) {
                    CommandHistorySidebar(
                        server: server,
                        onInsert: { command in
                            handleInsertCommand(command)
                        }
                    )
                    .inspectorColumnWidth(min: 220, ideal: 280, max: 400)
                }
                .alert(
                    "Enable Quick Insert?",
                    isPresented: $showQuickInsertAlert
                ) {
                    Button("Enable") {
                        commandHistory.quickInsertEnabled = true
                        commandHistory.hasAskedAboutQuickInsert = true
                        if let cmd = pendingInsertCommand {
                            writeToTerminal(cmd)
                            pendingInsertCommand = nil
                        }
                    }
                    Button("Disable", role: .cancel) {
                        commandHistory.quickInsertEnabled = false
                        commandHistory.hasAskedAboutQuickInsert = true
                        pendingInsertCommand = nil
                    }
                } message: {
                    Text("Commands will be pasted directly into your terminal. You can change this in the command history sidebar.")
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

    private func handleInsertCommand(_ command: String) {
        if !commandHistory.hasAskedAboutQuickInsert {
            pendingInsertCommand = command
            showQuickInsertAlert = true
        } else if commandHistory.quickInsertEnabled {
            writeToTerminal(command)
        }
    }

    private func writeToTerminal(_ command: String) {
        guard terminalFD >= 0 else { return }
        let data = Data(command.utf8)
        let fd = terminalFD
        data.withUnsafeBytes { ptr in
            _ = write(fd, ptr.baseAddress!, ptr.count)
        }
    }
}

// MARK: - Command History Sidebar

private struct CommandHistorySidebar: View {
    let server: Server
    let onInsert: (String) -> Void
    @Environment(CommandHistoryManager.self) private var commandHistory

    private var recentCommands: [CommandEntry] {
        Array(
            commandHistory.history
                .filter { $0.serverID == server.id }
                .suffix(50)
                .reversed()
        )
    }

    var body: some View {
        @Bindable var history = commandHistory

        Form {
            Section {
                Toggle("Quick Insert", isOn: $history.quickInsertEnabled)
            }

            Section("Favourites") {
                if commandHistory.favourites.isEmpty {
                    Text("No favourites yet")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                } else {
                    ForEach(commandHistory.favourites) { entry in
                        CommandRow(
                            entry: entry,
                            isFavourite: true,
                            onInsert: { onInsert(entry.command) },
                            onToggleFavourite: { commandHistory.toggleFavourite(entry) }
                        )
                    }
                }
            }

            Section("Recent") {
                if recentCommands.isEmpty {
                    Text("No commands yet")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                } else {
                    ForEach(recentCommands) { entry in
                        CommandRow(
                            entry: entry,
                            isFavourite: commandHistory.isFavourite(entry.command),
                            onInsert: { onInsert(entry.command) },
                            onToggleFavourite: { commandHistory.toggleFavourite(entry) }
                        )
                    }
                }
            }

            Section {
                Button("Clear History", role: .destructive) {
                    commandHistory.clearHistory()
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Command Row

private struct CommandRow: View {
    let entry: CommandEntry
    let isFavourite: Bool
    let onInsert: () -> Void
    let onToggleFavourite: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onInsert) {
                Text(entry.command)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onToggleFavourite) {
                Image(systemName: isFavourite ? "star.fill" : "star")
                    .foregroundStyle(isFavourite ? .yellow : .secondary)
                    .font(.callout)
            }
            .buttonStyle(.plain)
        }
    }
}
