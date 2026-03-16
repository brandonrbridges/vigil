import SwiftUI
import Charts

struct DashboardView: View {
    let server: Server
    @Environment(ConnectionManager.self) private var connectionManager

    private var metrics: ServerMetrics {
        connectionManager.metrics[server.id] ?? .empty
    }

    var body: some View {
        Group {
            let state = connectionManager.connectionStates[server.id]
            switch state {
            case .connecting:
                ProgressView("Connecting to \(server.host)...")
            case .failed(let message):
                ContentUnavailableView(
                    "Connection Failed",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )
            case .connected:
                metricsForm
            default:
                ContentUnavailableView(
                    "Not Connected",
                    systemImage: "network.slash",
                    description: Text("Connect to \(server.host) to view metrics.")
                )
            }
        }
    }

    private var metricsForm: some View {
        Form {
            systemSection
            cpuSection
            memorySection
            diskSection
            networkSection
            servicesSection
        }
        .formStyle(.grouped)
        .animation(.smooth, value: metrics.timestamp)
    }

    // MARK: - System

    private var systemSection: some View {
        Section("System") {
            LabeledContent("Hostname", value: metrics.systemInfo.hostname.isEmpty ? "—" : metrics.systemInfo.hostname)
            LabeledContent("OS", value: [metrics.systemInfo.os, metrics.systemInfo.kernel].filter { !$0.isEmpty }.joined(separator: " "))
            LabeledContent("Uptime", value: metrics.systemInfo.uptime.isEmpty ? "—" : metrics.systemInfo.uptime)
        }
    }

    // MARK: - CPU

    private var cpuHistory: [CPUDataPoint] {
        connectionManager.cpuHistory[server.id] ?? []
    }

    private var cpuSection: some View {
        Section("CPU") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("\(metrics.cpu.usagePercent, specifier: "%.1f")%")
                        .font(.title2.monospacedDigit().bold())
                    Spacer()
                    Text("Load: \(String(format: "%.2f", metrics.cpu.loadAverage.one))  \(String(format: "%.2f", metrics.cpu.loadAverage.five))  \(String(format: "%.2f", metrics.cpu.loadAverage.fifteen))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                cpuChart
                .chartYScale(domain: 0...100)
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .trailing, values: [0, 50, 100]) { value in
                        AxisValueLabel {
                            if let v = value.as(Int.self) {
                                Text("\(v)%")
                                    .font(.caption2)
                            }
                        }
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                            .foregroundStyle(.quaternary)
                    }
                }
                .frame(height: 100)
            }
        }
    }

    // MARK: - Memory

    private var memorySection: some View {
        Section("Memory") {
            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: metrics.memory.usagePercent, total: 100) {
                    HStack {
                        Text("Usage")
                        Spacer()
                        Text("\(metrics.memory.usagePercent, specifier: "%.1f")%")
                            .monospacedDigit()
                    }
                    .font(.callout)
                }
                .tint(memoryTint)
            }

            LabeledContent("Used", value: formatMB(metrics.memory.usedMB))
            LabeledContent("Cached", value: formatMB(metrics.memory.cachedMB))
            LabeledContent("Free", value: formatMB(metrics.memory.freeMB))
            LabeledContent("Total", value: formatMB(metrics.memory.totalMB))
        }
    }

    private var cpuChart: some View {
        Chart(cpuHistory) { point in
            AreaMark(
                x: .value("Time", point.timestamp),
                y: .value("CPU", point.usage)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [Color.blue.opacity(0.3), Color.blue.opacity(0.05)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .interpolationMethod(.catmullRom)

            LineMark(
                x: .value("Time", point.timestamp),
                y: .value("CPU", point.usage)
            )
            .foregroundStyle(Color.blue)
            .interpolationMethod(.catmullRom)
            .lineStyle(StrokeStyle(lineWidth: 1.5))
        }
    }

    private var memoryTint: Color {
        let pct = metrics.memory.usagePercent
        if pct > 90 { return .red }
        if pct > 75 { return .orange }
        return .blue
    }

    // MARK: - Disk

    private var diskSection: some View {
        Section("Disk") {
            if metrics.disk.isEmpty {
                Text("No disk data available")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            } else {
                ForEach(metrics.disk) { disk in
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: disk.usagePercent, total: 100) {
                            HStack {
                                Text(disk.mountPoint)
                                    .font(.callout.bold())
                                Spacer()
                                Text("\(formatMB(disk.usedMB)) / \(formatMB(disk.sizeMB))")
                                    .font(.callout.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tint(disk.usagePercent > 90 ? .red : disk.usagePercent > 75 ? .orange : .blue)
                    }
                }
            }
        }
    }

    // MARK: - Network

    private var networkSection: some View {
        Section("Network") {
            LabeledContent {
                Text(formatBytes(metrics.network.bytesIn))
                    .monospacedDigit()
            } label: {
                Label("Received", systemImage: "arrow.down.circle.fill")
                    .foregroundStyle(.green)
            }

            LabeledContent {
                Text(formatBytes(metrics.network.bytesOut))
                    .monospacedDigit()
            } label: {
                Label("Sent", systemImage: "arrow.up.circle.fill")
                    .foregroundStyle(.blue)
            }

            LabeledContent {
                Text("\(metrics.network.activeConnections)")
                    .monospacedDigit()
            } label: {
                Label("Active Connections", systemImage: "point.3.connected.trianglepath.dotted")
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Services

    private var servicesSection: some View {
        Section("Services (\(metrics.services.count))") {
            if metrics.services.isEmpty {
                Text("No running services detected")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(metrics.services) { service in
                    LabeledContent {
                        Text(service.state.rawValue)
                            .font(.callout)
                            .foregroundStyle(colorForState(service.state))
                    } label: {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(colorForState(service.state))
                                .frame(width: 8, height: 8)
                            Text(service.name)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func formatMB(_ mb: Int) -> String {
        if mb >= 1024 {
            return String(format: "%.1f GB", Double(mb) / 1024.0)
        }
        return "\(mb) MB"
    }

    private static nonisolated(unsafe) let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter
    }()

    private func formatBytes(_ bytes: UInt64) -> String {
        Self.byteFormatter.string(fromByteCount: Int64(bytes))
    }

    private func colorForState(_ state: ServiceState) -> Color {
        switch state {
        case .active: .green
        case .inactive: .gray
        case .failed: .red
        case .activating, .deactivating: .orange
        case .unknown: .gray
        }
    }
}
