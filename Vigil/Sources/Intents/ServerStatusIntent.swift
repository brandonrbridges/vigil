import AppIntents

struct ServerStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Check Server Status"
    static let description: IntentDescription = "Check the status of a Vigil server"

    @Parameter(title: "Server Name")
    var serverName: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Check status of \(\.$serverName)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let manager = ServerManager.shared
        let connManager = ConnectionManager.shared

        let server: Server?
        if let name = serverName {
            server = manager.servers.first { $0.displayName.localizedCaseInsensitiveContains(name) }
        } else {
            server = manager.servers.first
        }

        guard let server else {
            return .result(value: "No servers found", dialog: "No servers are configured in Vigil.")
        }

        let state = connManager.connectionStates[server.id]
        let metrics = connManager.metrics[server.id]

        var status = "\(server.displayName): "
        switch state {
        case .connected:
            if let m = metrics {
                status += "Connected — CPU \(String(format: "%.1f", m.cpu.usagePercent))%, "
                status += "Memory \(String(format: "%.1f", m.memory.usagePercent))%, "
                status += "Uptime: \(m.systemInfo.uptime)"
            } else {
                status += "Connected (gathering metrics...)"
            }
        case .connecting: status += "Connecting..."
        case .failed(let msg): status += "Failed: \(msg)"
        case .disconnected, .none: status += "Disconnected — open Vigil to connect and monitor this server"
        }

        return .result(value: status, dialog: IntentDialog(stringLiteral: status))
    }
}

struct ListServersIntent: AppIntent {
    static let title: LocalizedStringResource = "List Vigil Servers"
    static let description: IntentDescription = "List all servers configured in Vigil"

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let manager = ServerManager.shared

        if manager.servers.isEmpty {
            return .result(value: "No servers", dialog: "No servers are configured in Vigil.")
        }

        let list = manager.servers.map { "\($0.displayName) (\($0.host))" }.joined(separator: "\n")
        return .result(value: list, dialog: IntentDialog(stringLiteral: "Servers:\n\(list)"))
    }
}

struct VigilShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ServerStatusIntent(),
            phrases: [
                "Check server status in \(.applicationName)",
                "How are my servers in \(.applicationName)",
                "Server status \(.applicationName)"
            ],
            shortTitle: "Server Status",
            systemImageName: "server.rack"
        )
        AppShortcut(
            intent: ListServersIntent(),
            phrases: [
                "List servers in \(.applicationName)",
                "Show my servers in \(.applicationName)"
            ],
            shortTitle: "List Servers",
            systemImageName: "list.bullet"
        )
    }
}
