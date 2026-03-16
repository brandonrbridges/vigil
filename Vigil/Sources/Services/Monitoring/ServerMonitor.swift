import Foundation

actor ServerMonitor {
    let connection: SSHConnection
    private var pollTask: Task<Void, Never>?
    private var metricsHandler: ((ServerMetrics) -> Void)?

    init(connection: SSHConnection) {
        self.connection = connection
    }

    func startPolling(interval: TimeInterval = 5, handler: @escaping @Sendable (ServerMetrics) -> Void) {
        metricsHandler = handler
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                let metrics = await fetchMetrics()
                handler(metrics)
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func fetchMetrics() async -> ServerMetrics {
        // Run all metric commands in parallel
        async let topResult = safeExecute("top -bn1 | head -5")
        async let freeResult = safeExecute("free -m")
        async let dfResult = safeExecute("df -m")
        async let ipResult = safeExecute("ip -s link")
        async let ssResult = safeExecute("ss -tun | wc -l")
        async let servicesResult = safeExecute("systemctl list-units --type=service --state=running --no-pager --no-legend")
        async let hostnameResult = safeExecute("hostname")
        async let unameResult = safeExecute("uname -srm")
        async let uptimeResult = safeExecute("uptime")

        let (top, free, df, ip, ss, services, hostname, uname, uptime) = await (
            topResult, freeResult, dfResult, ipResult, ssResult,
            servicesResult, hostnameResult, unameResult, uptimeResult
        )

        return ServerMetrics(
            cpu: MetricParser.parseCPU(from: top, uptimeOutput: uptime),
            memory: MetricParser.parseMemory(from: free),
            disk: MetricParser.parseDisk(from: df),
            network: MetricParser.parseNetwork(from: ip, ssOutput: ss),
            services: MetricParser.parseServices(from: services),
            systemInfo: MetricParser.parseSystemInfo(from: hostname, unameOutput: uname, uptimeOutput: uptime),
            timestamp: .now
        )
    }

    private func safeExecute(_ command: String) async -> String {
        do {
            return try await connection.execute(command)
        } catch {
            return ""
        }
    }
}
