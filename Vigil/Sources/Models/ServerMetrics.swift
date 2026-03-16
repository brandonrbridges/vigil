import Foundation

struct CPUDataPoint: Identifiable, Sendable {
    var id: Date { timestamp }
    let timestamp: Date
    let usage: Double
}

struct ServerMetrics: Sendable {
    var cpu: CPUMetrics
    var memory: MemoryMetrics
    var disk: [DiskMetrics]
    var network: NetworkMetrics
    var services: [ServiceStatus]
    var systemInfo: SystemInfo
    var timestamp: Date

    static let empty = ServerMetrics(
        cpu: .empty,
        memory: .empty,
        disk: [],
        network: .empty,
        services: [],
        systemInfo: .empty,
        timestamp: .now
    )
}

struct LoadAverage: Sendable {
    var one: Double
    var five: Double
    var fifteen: Double

    static let empty = LoadAverage(one: 0, five: 0, fifteen: 0)
}

struct CPUMetrics: Sendable {
    var usagePercent: Double
    var loadAverage: LoadAverage

    static let empty = CPUMetrics(usagePercent: 0, loadAverage: .empty)
}

struct MemoryMetrics: Sendable {
    var totalMB: Int
    var usedMB: Int
    var cachedMB: Int
    var freeMB: Int

    var usagePercent: Double {
        guard totalMB > 0 else { return 0 }
        return Double(usedMB) / Double(totalMB) * 100
    }

    static let empty = MemoryMetrics(totalMB: 0, usedMB: 0, cachedMB: 0, freeMB: 0)
}

struct DiskMetrics: Sendable, Identifiable {
    var id: String { mountPoint }
    var filesystem: String
    var sizeMB: Int
    var usedMB: Int
    var availableMB: Int
    var mountPoint: String

    var usagePercent: Double {
        guard sizeMB > 0 else { return 0 }
        return Double(usedMB) / Double(sizeMB) * 100
    }
}

struct NetworkMetrics: Sendable {
    var bytesIn: UInt64
    var bytesOut: UInt64
    var activeConnections: Int

    static let empty = NetworkMetrics(bytesIn: 0, bytesOut: 0, activeConnections: 0)
}

struct ServiceStatus: Sendable, Identifiable {
    var id: String { name }
    var name: String
    var state: ServiceState
    var subState: String
}

enum ServiceState: String, Sendable, Codable {
    case active
    case inactive
    case failed
    case activating
    case deactivating
    case unknown
}

struct SystemInfo: Sendable {
    var hostname: String
    var os: String
    var kernel: String
    var uptime: String

    static let empty = SystemInfo(hostname: "", os: "", kernel: "", uptime: "")
}
