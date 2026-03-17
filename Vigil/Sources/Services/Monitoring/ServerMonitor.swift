import Foundation

actor ServerMonitor {
    let connection: SSHConnection
    private var pollTask: Task<Void, Never>?
    /// Single combined command that collects all metrics in one SSH call.
    /// Each section is delimited by a marker line for reliable parsing.
    private static let metricsCommand = """
    echo '---TOP---' && top -bn1 | head -5 && \
    echo '---FREE---' && free -m && \
    echo '---DF---' && df -m && \
    echo '---IP---' && ip -s link && \
    echo '---SS---' && ss -tun | wc -l && \
    echo '---SERVICES---' && systemctl list-units --type=service --state=running --no-pager --no-legend && \
    echo '---HOSTNAME---' && hostname && \
    echo '---UNAME---' && uname -srm && \
    echo '---UPTIME---' && uptime -p 2>/dev/null || uptime
    """

    init(connection: SSHConnection) {
        self.connection = connection
    }

    func startPolling(settings: AppSettings?, handler: @escaping @Sendable (ServerMetrics) -> Void) {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                let metrics = await fetchMetrics()
                handler(metrics)
                let interval = await MainActor.run { settings?.pollingInterval ?? 5 }
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func fetchMetrics() async -> ServerMetrics {
        // Single SSH call for all metrics
        let output: String
        do {
            output = try await connection.execute(Self.metricsCommand)
        } catch {
            return .empty
        }

        let sections = parseSections(output)

        return ServerMetrics(
            cpu: MetricParser.parseCPU(
                from: sections["TOP"] ?? "",
                uptimeOutput: sections["UPTIME"] ?? ""
            ),
            memory: MetricParser.parseMemory(from: sections["FREE"] ?? ""),
            disk: MetricParser.parseDisk(from: sections["DF"] ?? ""),
            network: MetricParser.parseNetwork(
                from: sections["IP"] ?? "",
                ssOutput: sections["SS"] ?? ""
            ),
            services: MetricParser.parseServices(from: sections["SERVICES"] ?? ""),
            systemInfo: MetricParser.parseSystemInfo(
                from: sections["HOSTNAME"] ?? "",
                unameOutput: sections["UNAME"] ?? "",
                uptimeOutput: sections["UPTIME"] ?? ""
            ),
            timestamp: .now
        )
    }

    /// Parse the combined output into named sections using ---MARKER--- delimiters.
    private func parseSections(_ output: String) -> [String: String] {
        var sections: [String: String] = [:]
        var currentKey: String?
        var currentLines: [String] = []

        for line in output.components(separatedBy: "\n") {
            if line.hasPrefix("---") && line.hasSuffix("---") {
                // Save previous section
                if let key = currentKey {
                    sections[key] = currentLines.joined(separator: "\n")
                }
                // Start new section
                currentKey = String(line.dropFirst(3).dropLast(3))
                currentLines = []
            } else {
                currentLines.append(line)
            }
        }
        // Save last section
        if let key = currentKey {
            sections[key] = currentLines.joined(separator: "\n")
        }

        return sections
    }
}
