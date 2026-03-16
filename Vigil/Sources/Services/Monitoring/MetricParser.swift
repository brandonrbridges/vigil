import Foundation

struct MetricParser {

    // MARK: - CPU & Load

    static func parseCPU(from topOutput: String, uptimeOutput: String) -> CPUMetrics {
        // Parse CPU from top -bn1: "%Cpu(s):  1.2 us,  0.5 sy, ..."
        var usage = 0.0
        if let cpuLine = topOutput.split(separator: "\n").first(where: { $0.contains("%Cpu") || $0.contains("Cpu(s)") }) {
            let parts = String(cpuLine)
            // Extract idle percentage — CPU usage = 100 - idle
            if let idRange = parts.range(of: #"(\d+\.?\d*)\s*id"#, options: .regularExpression) {
                let idStr = parts[idRange].split(separator: " ").first ?? "0"
                let idle = Double(idStr) ?? 0
                usage = 100.0 - idle
            }
        }

        // Parse load averages from uptime: "load average: 0.12, 0.15, 0.10"
        var load = LoadAverage.empty
        if let loadRange = uptimeOutput.range(of: "load average:") {
            let loadStr = String(uptimeOutput[loadRange.upperBound...])
                .trimmingCharacters(in: .whitespaces)
            let parts = loadStr.split(separator: ",").map {
                Double($0.trimmingCharacters(in: .whitespaces)) ?? 0
            }
            if parts.count >= 3 {
                load = LoadAverage(one: parts[0], five: parts[1], fifteen: parts[2])
            }
        }

        return CPUMetrics(usagePercent: max(0, min(100, usage)), loadAverage: load)
    }

    // MARK: - Memory

    static func parseMemory(from freeOutput: String) -> MemoryMetrics {
        // Parse "free -m" output:
        // Mem:   total   used   free   shared  buff/cache  available
        let lines = freeOutput.split(separator: "\n")
        guard let memLine = lines.first(where: { $0.hasPrefix("Mem:") }) else {
            return .empty
        }

        let parts = memLine.split(whereSeparator: \.isWhitespace).map(String.init)
        guard parts.count >= 6 else { return .empty }

        let total = Int(parts[1]) ?? 0
        let used = Int(parts[2]) ?? 0
        let free = Int(parts[3]) ?? 0
        let cached = Int(parts[5]) ?? 0 // buff/cache column

        return MemoryMetrics(totalMB: total, usedMB: used, cachedMB: cached, freeMB: free)
    }

    // MARK: - Disk

    static func parseDisk(from dfOutput: String) -> [DiskMetrics] {
        // Parse "df -m" (megabytes) output
        let lines = dfOutput.split(separator: "\n").dropFirst() // skip header
        return lines.compactMap { line in
            let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard parts.count >= 6 else { return nil }
            let mountPoint = parts[5]
            // Skip pseudo-filesystems
            guard !mountPoint.hasPrefix("/snap"),
                  !parts[0].hasPrefix("tmpfs"),
                  !parts[0].hasPrefix("devtmpfs"),
                  !parts[0].hasPrefix("udev") else { return nil }

            return DiskMetrics(
                filesystem: parts[0],
                sizeMB: Int(parts[1]) ?? 0,
                usedMB: Int(parts[2]) ?? 0,
                availableMB: Int(parts[3]) ?? 0,
                mountPoint: mountPoint
            )
        }
    }

    // MARK: - Network

    static func parseNetwork(from ipOutput: String, ssOutput: String) -> NetworkMetrics {
        // Parse "ip -s link" for bytes in/out
        var totalIn: UInt64 = 0
        var totalOut: UInt64 = 0

        let lines = ipOutput.split(separator: "\n").map(String.init)
        var i = 0
        while i < lines.count {
            if lines[i].contains("RX:") && i + 1 < lines.count {
                let rxParts = lines[i + 1].split(whereSeparator: \.isWhitespace)
                if let bytes = rxParts.first.flatMap({ UInt64($0) }) {
                    totalIn += bytes
                }
            }
            if lines[i].contains("TX:") && i + 1 < lines.count {
                let txParts = lines[i + 1].split(whereSeparator: \.isWhitespace)
                if let bytes = txParts.first.flatMap({ UInt64($0) }) {
                    totalOut += bytes
                }
            }
            i += 1
        }

        // Parse active connections count from "ss -tun | wc -l"
        let connections = max(0, (Int(ssOutput.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 1) - 1)

        return NetworkMetrics(bytesIn: totalIn, bytesOut: totalOut, activeConnections: connections)
    }

    // MARK: - Services

    static func parseServices(from systemctlOutput: String) -> [ServiceStatus] {
        // Parse "systemctl list-units --type=service --no-pager --no-legend"
        let lines = systemctlOutput.split(separator: "\n")
        return lines.compactMap { line in
            let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard parts.count >= 4 else { return nil }

            let name = parts[0]
                .replacingOccurrences(of: ".service", with: "")
                .trimmingCharacters(in: .whitespaces)

            // Skip uninteresting system services
            let skipPrefixes = ["systemd-", "dbus", "polkit", "snapd."]
            if skipPrefixes.contains(where: { name.hasPrefix($0) }) { return nil }

            let activeStr = parts[2]
            let subState = parts[3]

            let state: ServiceState = switch activeStr {
            case "active": .active
            case "inactive": .inactive
            case "failed": .failed
            case "activating": .activating
            case "deactivating": .deactivating
            default: .unknown
            }

            return ServiceStatus(name: name, state: state, subState: subState)
        }
    }

    // MARK: - System Info

    static func parseSystemInfo(from hostnameOutput: String, unameOutput: String, uptimeOutput: String) -> SystemInfo {
        let hostname = hostnameOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        let kernelParts = unameOutput.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ")
        let os = kernelParts.count > 0 ? String(kernelParts[0]) : ""
        let kernel = kernelParts.count > 2 ? String(kernelParts[2]) : ""

        let uptime = parseUptime(uptimeOutput)

        return SystemInfo(hostname: hostname, os: os, kernel: kernel, uptime: uptime)
    }

    /// Parse uptime from either `uptime -p` ("up 3 days, 5 hours") or regular `uptime` output
    private static func parseUptime(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // `uptime -p` format: "up 3 days, 5 hours, 12 minutes"
        if trimmed.hasPrefix("up ") && !trimmed.contains("load average") {
            return String(trimmed.dropFirst(3))
        }

        // Regular `uptime` format: " 21:58:24 up 97 days, 9:23, 6 users, load average: ..."
        // Extract between "up " and the user count
        guard let upRange = trimmed.range(of: "up ") else { return trimmed }
        let afterUp = String(trimmed[upRange.upperBound...])

        // Find the "N user" marker and take everything before it
        if let userRange = afterUp.range(of: #"\d+\s+user"#, options: .regularExpression) {
            var uptimeStr = String(afterUp[..<userRange.lowerBound])
            // Remove trailing comma and whitespace
            uptimeStr = uptimeStr.trimmingCharacters(in: .whitespaces)
            if uptimeStr.hasSuffix(",") {
                uptimeStr = String(uptimeStr.dropLast())
            }
            return uptimeStr.trimmingCharacters(in: .whitespaces)
        }

        // Fallback: take up to first "load average"
        if let loadRange = afterUp.range(of: "load average") {
            var uptimeStr = String(afterUp[..<loadRange.lowerBound])
            uptimeStr = uptimeStr.trimmingCharacters(in: .whitespacesAndNewlines)
            if uptimeStr.hasSuffix(",") {
                uptimeStr = String(uptimeStr.dropLast())
            }
            return uptimeStr.trimmingCharacters(in: .whitespaces)
        }

        return afterUp.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
