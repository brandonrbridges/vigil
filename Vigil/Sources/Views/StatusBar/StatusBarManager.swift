import AppKit
import SwiftUI

@MainActor
final class StatusBarManager: NSObject {
    private var statusItem: NSStatusItem?
    private let serverManager: ServerManager
    private let connectionManager: ConnectionManager
    private var observationTask: Task<Void, Never>?

    init(serverManager: ServerManager, connectionManager: ConnectionManager) {
        self.serverManager = serverManager
        self.connectionManager = connectionManager
        super.init()
        setupStatusItem()
        startObserving()
    }

    deinit {
        observationTask?.cancel()
    }

    // MARK: - Setup

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateIcon()
        rebuildMenu()
    }

    private func startObserving() {
        observationTask = Task { [weak self] in
            // Poll for changes since @Observable doesn't provide a Combine publisher directly.
            // withObservationTracking re-fires each time a tracked property changes.
            while !Task.isCancelled {
                guard let self else { return }
                withObservationTracking {
                    _ = self.serverManager.servers
                    _ = self.connectionManager.connectionStates
                } onChange: {
                    Task { @MainActor [weak self] in
                        self?.updateIcon()
                        self?.rebuildMenu()
                    }
                }
                // Yield to avoid a tight loop; onChange fires on next run-loop turn.
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    // MARK: - Icon

    private func updateIcon() {
        guard let button = statusItem?.button else { return }

        let symbolName: String
        let tintColor: NSColor

        let overallHealth = computeOverallHealth()
        switch overallHealth {
        case .allGood:
            symbolName = "checkmark.circle.fill"
            tintColor = .systemGreen
        case .warning:
            symbolName = "exclamationmark.triangle.fill"
            tintColor = .systemYellow
        case .critical:
            symbolName = "xmark.circle.fill"
            tintColor = .systemRed
        case .noServers:
            symbolName = "server.rack"
            tintColor = .secondaryLabelColor
        }

        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Server status") {
            let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
            let configured = image.withSymbolConfiguration(config) ?? image
            configured.isTemplate = false
            button.image = configured
        }

        button.contentTintColor = tintColor
    }

    private enum OverallHealth {
        case allGood, warning, critical, noServers
    }

    private func computeOverallHealth() -> OverallHealth {
        let servers = serverManager.servers
        guard !servers.isEmpty else { return .noServers }

        let states = servers.compactMap { connectionManager.connectionStates[$0.id] }
        guard !states.isEmpty else { return .noServers }

        let hasFailed = states.contains { if case .failed = $0 { return true } else { return false } }
        if hasFailed { return .critical }

        let hasConnecting = states.contains { $0 == .connecting }
        let hasDisconnected = states.contains { $0 == .disconnected }
        if hasConnecting || hasDisconnected { return .warning }

        return .allGood
    }

    // MARK: - Menu

    private func rebuildMenu() {
        let menu = NSMenu()

        let servers = serverManager.servers
        if servers.isEmpty {
            let noServers = NSMenuItem(title: "No servers configured", action: nil, keyEquivalent: "")
            noServers.isEnabled = false
            menu.addItem(noServers)
        } else {
            for server in servers {
                let state = connectionManager.connectionStates[server.id] ?? .disconnected
                let dot = statusDot(for: state)
                let title = "\(dot)  \(server.displayName)  —  \(server.host)"
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        let openItem = NSMenuItem(title: "Open Vigil", action: #selector(openApp), keyEquivalent: "o")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Vigil", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    private func statusDot(for state: ConnectionManager.ConnectionState) -> String {
        switch state {
        case .connected:
            return "\u{1F7E2}" // green circle
        case .connecting:
            return "\u{1F7E1}" // yellow circle
        case .disconnected:
            return "\u{26AA}"  // white circle
        case .failed:
            return "\u{1F534}" // red circle
        }
    }

    // MARK: - Actions

    @objc private func openApp() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        if let window = NSApplication.shared.windows.first {
            window.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
