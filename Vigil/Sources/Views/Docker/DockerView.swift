import SwiftUI

struct DockerView: View {
    let server: Server
    @Environment(ConnectionManager.self) private var connectionManager
    @State private var containers: [DockerContainer] = []
    @State private var selectedContainerID: String?
    @State private var showInspector = false
    @State private var isLoading = true
    @State private var searchText = ""

    private var filteredContainers: [DockerContainer] {
        if searchText.isEmpty { return containers }
        return containers.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.image.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var selectedContainer: DockerContainer? {
        guard let id = selectedContainerID else { return nil }
        return containers.first { $0.id == id }
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading containers...")
            } else if containers.isEmpty {
                ContentUnavailableView(
                    "No Containers",
                    systemImage: "shippingbox",
                    description: Text("No Docker containers found on this server.\nIs Docker installed and running?")
                )
            } else {
                containerTable
            }
        }
        .searchable(text: $searchText, prompt: "Filter containers")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    Task { await refreshContainers() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: .command)
            }

            if !containers.isEmpty {
                ToolbarItem(placement: .automatic) {
                    Button {
                        showInspector.toggle()
                    } label: {
                        Label("Inspector", systemImage: "sidebar.right")
                    }
                }
            }
        }
        .task(id: server.id) {
            if let prefetched = connectionManager.dockerContainers[server.id], !prefetched.isEmpty {
                containers = prefetched
                isLoading = false
            } else {
                await refreshContainers()
            }
            // Structured polling loop - automatically cancelled when server.id changes or view disappears
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled else { break }
                await refreshContainers()
            }
        }
    }

    private var containerTable: some View {
        Table(filteredContainers, selection: $selectedContainerID) {
            TableColumn("Status") { container in
                HStack(spacing: 6) {
                    Circle()
                        .fill(container.state.isRunning ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                        .accessibilityLabel("Status: \(container.state.rawValue)")
                    Text(container.state.rawValue)
                        .font(.callout)
                }
            }
            .width(min: 80, ideal: 100)

            TableColumn("Name") { container in
                Text(container.name)
                    .font(.callout.bold())
            }
            .width(min: 120, ideal: 200)

            TableColumn("Image") { container in
                Text(container.image)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .width(min: 120, ideal: 200)

            TableColumn("CPU") { container in
                Text(container.state.isRunning ? String(format: "%.1f%%", container.cpuPercent) : "—")
                    .font(.callout.monospacedDigit())
            }
            .width(min: 60, ideal: 80)

            TableColumn("Memory") { container in
                Text(container.state.isRunning ? formatMB(container.memoryUsageMB) : "—")
                    .font(.callout.monospacedDigit())
            }
            .width(min: 80, ideal: 100)

            TableColumn("Ports") { container in
                Text(container.ports.isEmpty ? "—" : container.ports)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .width(min: 80, ideal: 150)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            if let id = ids.first, let container = containers.first(where: { $0.id == id }) {
                Button("Start", systemImage: "play.fill") {
                    performAction { docker in try await docker.startContainer(container.id) }
                }
                .disabled(container.state.isRunning)
                .accessibilityLabel("Start container")

                Button("Stop", systemImage: "stop.fill") {
                    performAction { docker in try await docker.stopContainer(container.id) }
                }
                .disabled(!container.state.isRunning)
                .accessibilityLabel("Stop container")

                Button("Restart", systemImage: "arrow.clockwise") {
                    performAction { docker in try await docker.restartContainer(container.id) }
                }
                .accessibilityLabel("Restart container")

                Divider()

                Button("View Logs", systemImage: "doc.text") {
                    selectedContainerID = id
                    showInspector = true
                }
            }
        } primaryAction: { ids in
            if let id = ids.first {
                selectedContainerID = id
                showInspector.toggle()
            }
        }
        .inspector(isPresented: $showInspector) {
            if let container = selectedContainer {
                ContainerInspector(
                    server: server,
                    container: container,
                    onAction: { await refreshContainers() }
                )
            } else {
                ContentUnavailableView("No Container Selected", systemImage: "shippingbox", description: Text("Select a container to view its details."))
                    .inspectorColumnWidth(min: 300, ideal: 360, max: 450)
            }
        }
    }

    private func performAction(_ action: @escaping (DockerService) async throws -> Void) {
        guard let docker = connectionManager.dockerService(for: server.id) else { return }
        Task {
            try? await action(docker)
            try? await Task.sleep(for: .seconds(1))
            await refreshContainers()
        }
    }

    private func refreshContainers() async {
        guard let docker = connectionManager.dockerService(for: server.id) else {
            isLoading = false
            return
        }
        let result = await docker.listContainers()
        containers = result
        isLoading = false
    }

    private func formatMB(_ mb: Double) -> String {
        if mb >= 1024 {
            return String(format: "%.1f GB", mb / 1024.0)
        }
        return String(format: "%.0f MB", mb)
    }
}

struct ContainerInspector: View {
    let server: Server
    let container: DockerContainer
    let onAction: () async -> Void
    @Environment(ConnectionManager.self) private var connectionManager
    @State private var logs: String = "Loading..."
    @State private var isPerformingAction = false

    var body: some View {
        Form {
            Section("Container") {
                LabeledContent("Name", value: container.name)
                LabeledContent("Image", value: container.image)
                LabeledContent("Status", value: container.status)
                LabeledContent("ID", value: String(container.id.prefix(12)))
            }

            if container.state.isRunning {
                Section("Resources") {
                    LabeledContent("CPU", value: String(format: "%.1f%%", container.cpuPercent))
                    LabeledContent("Memory") {
                        Text(String(format: "%.0f / %.0f MB", container.memoryUsageMB, container.memoryLimitMB))
                            .monospacedDigit()
                    }
                    ProgressView(value: container.memoryPercent, total: 100) {
                        Text("Memory Usage")
                            .font(.caption)
                    }
                }
            }

            if !container.ports.isEmpty {
                Section("Networking") {
                    Text(container.ports)
                        .font(.callout)
                }
            }

            Section("Actions") {
                HStack(spacing: 12) {
                    Button("Start", systemImage: "play.fill") {
                        performAction { docker in try await docker.startContainer(container.id) }
                    }
                    .disabled(container.state.isRunning || isPerformingAction)
                    .accessibilityLabel("Start container")

                    Button("Stop", systemImage: "stop.fill") {
                        performAction { docker in try await docker.stopContainer(container.id) }
                    }
                    .disabled(!container.state.isRunning || isPerformingAction)
                    .accessibilityLabel("Stop container")

                    Button("Restart", systemImage: "arrow.clockwise") {
                        performAction { docker in try await docker.restartContainer(container.id) }
                    }
                    .disabled(isPerformingAction)
                    .accessibilityLabel("Restart container")
                }
            }

            Section("Logs") {
                ScrollView {
                    Text(logs)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(minHeight: 200)
            }
        }
        .formStyle(.grouped)
        .inspectorColumnWidth(min: 300, ideal: 360, max: 450)
        .task(id: container.id) {
            await fetchLogs()
        }
    }

    private func fetchLogs() async {
        guard let docker = connectionManager.dockerService(for: server.id) else { return }
        let result = await docker.logs(for: container.id)
        logs = result
    }

    private func performAction(_ action: @escaping (DockerService) async throws -> Void) {
        guard let docker = connectionManager.dockerService(for: server.id) else { return }
        isPerformingAction = true
        Task {
            try? await action(docker)
            try? await Task.sleep(for: .seconds(1)) // Let Docker settle
            await onAction()
            await MainActor.run { isPerformingAction = false }
        }
    }
}
