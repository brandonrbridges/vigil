import Foundation
import SwiftUI

@MainActor @Observable
final class ConnectionManager {
    private var connections: [UUID: SSHConnection] = [:]
    private var monitors: [UUID: ServerMonitor] = [:]
    private var dockerServices: [UUID: DockerService] = [:]
    private var sftpServices: [UUID: SFTPService] = [:]
    private var prefetchTasks: [UUID: Task<Void, Never>] = [:]
    var metrics: [UUID: ServerMetrics] = [:]
    var cpuHistory: [UUID: [CPUDataPoint]] = [:]
    var dockerContainers: [UUID: [DockerContainer]] = [:]
    var connectionStates: [UUID: ConnectionState] = [:]

    private let maxHistoryPoints = 60

    enum ConnectionState: Equatable, Sendable {
        case disconnected
        case connecting
        case connected
        case failed(String)
    }

    /// Test a connection without saving — used by the Welcome screen
    nonisolated func testConnection(for server: Server) async throws {
        let connection = SSHConnection(server: server)
        try await connection.testConnection()
    }

    /// Connect and start monitoring a server
    func connect(to server: Server) async {
        connectionStates[server.id] = .connecting
        let connection = SSHConnection(server: server)

        do {
            try await connection.testConnection()
            connections[server.id] = connection
            connectionStates[server.id] = .connected

            let monitor = ServerMonitor(connection: connection)
            monitors[server.id] = monitor

            let serverID = server.id
            await monitor.startPolling { [weak self] newMetrics in
                Task { @MainActor in
                    self?.metrics[serverID] = newMetrics
                    // Track CPU history
                    let point = CPUDataPoint(timestamp: newMetrics.timestamp, usage: newMetrics.cpu.usagePercent)
                    var history = self?.cpuHistory[serverID] ?? []
                    history.append(point)
                    if history.count > (self?.maxHistoryPoints ?? 60) {
                        history.removeFirst(history.count - (self?.maxHistoryPoints ?? 60))
                    }
                    self?.cpuHistory[serverID] = history
                }
            }
            // Pre-fetch Docker containers
            let docker = DockerService(connection: connection)
            let serverIDForDocker = server.id
            prefetchTasks[server.id] = Task {
                let containers = await docker.listContainers()
                await MainActor.run {
                    self.dockerContainers[serverIDForDocker] = containers
                    self.prefetchTasks.removeValue(forKey: serverIDForDocker)
                }
            }
        } catch {
            connectionStates[server.id] = .failed(error.localizedDescription)
        }
    }

    /// Disconnect a server
    func disconnect(from server: Server) async {
        if let monitor = monitors[server.id] {
            await monitor.stopPolling()
        }
        prefetchTasks[server.id]?.cancel()
        prefetchTasks.removeValue(forKey: server.id)
        monitors.removeValue(forKey: server.id)
        connections.removeValue(forKey: server.id)
        dockerServices.removeValue(forKey: server.id)
        sftpServices.removeValue(forKey: server.id)
        metrics.removeValue(forKey: server.id)
        connectionStates[server.id] = .disconnected
    }

    func connection(for serverID: UUID) -> SSHConnection? {
        connections[serverID]
    }

    func dockerService(for serverID: UUID) -> DockerService? {
        if let cached = dockerServices[serverID] { return cached }
        guard let connection = connections[serverID] else { return nil }
        let service = DockerService(connection: connection)
        dockerServices[serverID] = service
        return service
    }

    func sftpService(for serverID: UUID) -> SFTPService? {
        if let cached = sftpServices[serverID] { return cached }
        guard let connection = connections[serverID] else { return nil }
        let service = SFTPService(connection: connection)
        sftpServices[serverID] = service
        return service
    }
}
