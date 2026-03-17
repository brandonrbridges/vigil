import Foundation
import SwiftUI

@MainActor
@Observable
final class ServerManager {
    static let shared = ServerManager()

    var servers: [Server] = []
    var selectedServerID: UUID?

    private let storageURL: URL
    private var saveTask: Task<Void, Never>?

    var selectedServer: Server? {
        guard let id = selectedServerID else { return nil }
        return servers.first { $0.id == id }
    }

    init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("Vigil", isDirectory: true)

        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        self.storageURL = appSupport.appendingPathComponent("servers.json")

        loadServers()
    }

    func addServer(_ server: Server) {
        servers.append(server)
        if selectedServerID == nil {
            selectedServerID = server.id
        }
        saveServers()
    }

    func removeServer(_ server: Server) {
        servers.removeAll { $0.id == server.id }
        if selectedServerID == server.id {
            selectedServerID = servers.first?.id
        }
        saveServers()
        Task {
            try? await KeychainService.shared.deletePassword(for: server)
        }
    }

    func updateServer(_ server: Server) {
        if let index = servers.firstIndex(where: { $0.id == server.id }) {
            servers[index] = server
            saveServers()
        }
    }

    func selectServer(_ id: UUID?) {
        selectedServerID = id
        scheduleSave()
    }

    /// Persist the current selection without changing it.
    func persistSelection() {
        scheduleSave()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            saveServers()
        }
    }

    private func loadServers() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: storageURL)
            // Try new format first, fall back to legacy array format
            if let snapshot = try? JSONDecoder().decode(ServerSnapshot.self, from: data) {
                servers = snapshot.servers
                selectedServerID = snapshot.selectedServerID ?? servers.first?.id
            } else {
                servers = try JSONDecoder().decode([Server].self, from: data)
                selectedServerID = servers.first?.id
            }
        } catch {
            print("Failed to load servers: \(error)")
        }
    }

    private func saveServers() {
        do {
            let snapshot = ServerSnapshot(servers: servers, selectedServerID: selectedServerID)
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            print("Failed to save servers: \(error)")
        }
    }
}

private struct ServerSnapshot: Codable {
    var servers: [Server]
    var selectedServerID: UUID?

    init(servers: [Server], selectedServerID: UUID?) {
        self.servers = servers
        self.selectedServerID = selectedServerID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        servers = try container.decodeIfPresent([Server].self, forKey: .servers) ?? []
        selectedServerID = try container.decodeIfPresent(UUID.self, forKey: .selectedServerID)
    }
}
