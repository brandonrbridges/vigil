import Foundation

@MainActor
@Observable
final class AppSettings {
    // MARK: - General

    var pollingInterval: TimeInterval = 5
    var defaultUsername: String = "root"
    var defaultSSHKeyPath: String = ""
    var launchAtLogin: Bool = false

    // MARK: - Notifications

    var notificationsEnabled: Bool = true
    var notifyServerUnreachable: Bool = true
    var notifyCPUAboveThreshold: Bool = true
    var cpuThreshold: Double = 90
    var notifyDiskAboveThreshold: Bool = true
    var diskThreshold: Double = 90
    var notifyContainerStopped: Bool = true

    // MARK: - Persistence

    static let `default` = AppSettings()

    private static let settingsURL: URL = {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("Vigil", isDirectory: true)

        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return appSupport.appendingPathComponent("settings.json")
    }()

    init() {
        load()
    }

    func save() {
        let snapshot = SettingsSnapshot(
            pollingInterval: pollingInterval,
            defaultUsername: defaultUsername,
            defaultSSHKeyPath: defaultSSHKeyPath,
            launchAtLogin: launchAtLogin,
            notificationsEnabled: notificationsEnabled,
            notifyServerUnreachable: notifyServerUnreachable,
            notifyCPUAboveThreshold: notifyCPUAboveThreshold,
            cpuThreshold: cpuThreshold,
            notifyDiskAboveThreshold: notifyDiskAboveThreshold,
            diskThreshold: diskThreshold,
            notifyContainerStopped: notifyContainerStopped
        )
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(snapshot)
            try data.write(to: Self.settingsURL, options: .atomic)
        } catch {
            print("Failed to save settings: \(error)")
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: Self.settingsURL.path) else { return }
        do {
            let data = try Data(contentsOf: Self.settingsURL)
            let snapshot = try JSONDecoder().decode(SettingsSnapshot.self, from: data)
            pollingInterval = snapshot.pollingInterval
            defaultUsername = snapshot.defaultUsername
            defaultSSHKeyPath = snapshot.defaultSSHKeyPath
            launchAtLogin = snapshot.launchAtLogin
            notificationsEnabled = snapshot.notificationsEnabled
            notifyServerUnreachable = snapshot.notifyServerUnreachable
            notifyCPUAboveThreshold = snapshot.notifyCPUAboveThreshold
            cpuThreshold = snapshot.cpuThreshold
            notifyDiskAboveThreshold = snapshot.notifyDiskAboveThreshold
            diskThreshold = snapshot.diskThreshold
            notifyContainerStopped = snapshot.notifyContainerStopped
        } catch {
            print("Failed to load settings: \(error)")
        }
    }
}

private struct SettingsSnapshot: Codable {
    var pollingInterval: TimeInterval
    var defaultUsername: String
    var defaultSSHKeyPath: String
    var launchAtLogin: Bool
    var notificationsEnabled: Bool
    var notifyServerUnreachable: Bool
    var notifyCPUAboveThreshold: Bool
    var cpuThreshold: Double
    var notifyDiskAboveThreshold: Bool
    var diskThreshold: Double
    var notifyContainerStopped: Bool
}
