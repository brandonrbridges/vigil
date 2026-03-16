import Foundation

struct DockerContainer: Identifiable, Sendable {
    var id: String
    var name: String
    var image: String
    var status: String
    var state: ContainerState
    var ports: String
    var cpuPercent: Double
    var memoryUsageMB: Double
    var memoryLimitMB: Double

    var memoryPercent: Double {
        guard memoryLimitMB > 0 else { return 0 }
        return memoryUsageMB / memoryLimitMB * 100
    }
}

enum ContainerState: String, Sendable {
    case running
    case exited
    case paused
    case restarting
    case created
    case dead
    case unknown

    var isRunning: Bool { self == .running }
}
