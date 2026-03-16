import Foundation

enum DockerError: Error, LocalizedError {
    case invalidContainerID(String)

    var errorDescription: String? {
        switch self {
        case .invalidContainerID(let id):
            "Invalid container ID: \(id)"
        }
    }
}

actor DockerService {
    let connection: SSHConnection

    init(connection: SSHConnection) {
        self.connection = connection
    }

    /// Validate that a container ID/name contains only safe characters
    private func sanitizeContainerID(_ id: String) throws -> String {
        let pattern = /^[a-zA-Z0-9_.\-]+$/
        guard id.wholeMatch(of: pattern) != nil else {
            throw DockerError.invalidContainerID(id)
        }
        return id
    }

    /// Fetch all containers (running and stopped)
    func listContainers() async -> [DockerContainer] {
        // Get container list
        guard let psOutput = try? await connection.execute(
            "docker ps -a --format '{{.ID}}\\t{{.Names}}\\t{{.Image}}\\t{{.Status}}\\t{{.State}}\\t{{.Ports}}'"
        ) else {
            return []
        }

        // Get stats for running containers
        let statsMap = await fetchStats()

        let lines = psOutput.split(separator: "\n")
        return lines.compactMap { line in
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 6 else { return nil }

            let id = parts[0]
            let name = parts[1]
            let image = parts[2]
            let status = parts[3]
            let stateStr = parts[4].lowercased()
            let ports = parts[5]

            let state: ContainerState = switch stateStr {
            case "running": .running
            case "exited": .exited
            case "paused": .paused
            case "restarting": .restarting
            case "created": .created
            case "dead": .dead
            default: .unknown
            }

            let stats = statsMap[id] ?? statsMap[name]

            return DockerContainer(
                id: id,
                name: name,
                image: image,
                status: status,
                state: state,
                ports: ports,
                cpuPercent: stats?.cpu ?? 0,
                memoryUsageMB: stats?.memUsage ?? 0,
                memoryLimitMB: stats?.memLimit ?? 0
            )
        }
    }

    /// Start a container
    func startContainer(_ id: String) async throws {
        let safeID = try sanitizeContainerID(id)
        _ = try await connection.execute("docker start \(safeID)")
    }

    /// Stop a container
    func stopContainer(_ id: String) async throws {
        let safeID = try sanitizeContainerID(id)
        _ = try await connection.execute("docker stop \(safeID)")
    }

    /// Restart a container
    func restartContainer(_ id: String) async throws {
        let safeID = try sanitizeContainerID(id)
        _ = try await connection.execute("docker restart \(safeID)")
    }

    /// Fetch recent logs for a container
    func logs(for id: String, tail: Int = 100) async -> String {
        guard let safeID = try? sanitizeContainerID(id) else { return "Invalid container ID" }
        return (try? await connection.execute("docker logs --tail \(tail) \(safeID) 2>&1")) ?? "Unable to fetch logs"
    }

    // MARK: - Stats parsing

    private struct ContainerStats {
        let cpu: Double
        let memUsage: Double
        let memLimit: Double
    }

    private func fetchStats() async -> [String: ContainerStats] {
        guard let output = try? await connection.execute(
            "docker stats --no-stream --format '{{.ID}}\\t{{.Name}}\\t{{.CPUPerc}}\\t{{.MemUsage}}'"
        ) else {
            return [:]
        }

        var map: [String: ContainerStats] = [:]

        for line in output.split(separator: "\n") {
            let parts = line.split(separator: "\t").map(String.init)
            guard parts.count >= 4 else { continue }

            let id = parts[0]
            let name = parts[1]
            let cpu = Double(parts[2].replacingOccurrences(of: "%", with: "")) ?? 0

            // Parse "123.4MiB / 1.5GiB"
            let memParts = parts[3].split(separator: "/").map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            let memUsage = parseMemory(memParts.first ?? "0")
            let memLimit = parseMemory(memParts.count > 1 ? memParts[1] : "0")

            let stats = ContainerStats(cpu: cpu, memUsage: memUsage, memLimit: memLimit)
            map[id] = stats
            map[name] = stats
        }

        return map
    }

    /// Parse Docker memory strings like "123.4MiB" or "1.5GiB" into MB
    private func parseMemory(_ str: String) -> Double {
        let cleaned = str.trimmingCharacters(in: .whitespaces)
        if cleaned.hasSuffix("GiB") {
            return (Double(cleaned.dropLast(3)) ?? 0) * 1024
        } else if cleaned.hasSuffix("MiB") {
            return Double(cleaned.dropLast(3)) ?? 0
        } else if cleaned.hasSuffix("KiB") {
            return (Double(cleaned.dropLast(3)) ?? 0) / 1024
        } else if cleaned.hasSuffix("B") {
            return (Double(cleaned.dropLast(1)) ?? 0) / (1024 * 1024)
        }
        return Double(cleaned) ?? 0
    }
}
