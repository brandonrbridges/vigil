import Foundation

@MainActor
@Observable
final class AppSettings {
    // MARK: - General

    var pollingInterval: TimeInterval = 5
    var defaultUsername: String = "root"
    var defaultSSHKeyPath: String = ""

    // MARK: - Notifications

    var notificationsEnabled: Bool = true
    var notifyServerUnreachable: Bool = true
    var notifyCPUAboveThreshold: Bool = true
    var cpuThreshold: Double = 90
    var notifyDiskAboveThreshold: Bool = true
    var diskThreshold: Double = 90

    // MARK: - Persistence

    private var saveTask: Task<Void, Never>?

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

    func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            save()
        }
    }

    func save() {
        let snapshot = SettingsSnapshot(
            pollingInterval: pollingInterval,
            defaultUsername: defaultUsername,
            defaultSSHKeyPath: defaultSSHKeyPath,
            notificationsEnabled: notificationsEnabled,
            notifyServerUnreachable: notifyServerUnreachable,
            notifyCPUAboveThreshold: notifyCPUAboveThreshold,
            cpuThreshold: cpuThreshold,
            notifyDiskAboveThreshold: notifyDiskAboveThreshold,
            diskThreshold: diskThreshold
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
            notificationsEnabled = snapshot.notificationsEnabled
            notifyServerUnreachable = snapshot.notifyServerUnreachable
            notifyCPUAboveThreshold = snapshot.notifyCPUAboveThreshold
            cpuThreshold = snapshot.cpuThreshold
            notifyDiskAboveThreshold = snapshot.notifyDiskAboveThreshold
            diskThreshold = snapshot.diskThreshold
        } catch {
            print("Failed to load settings: \(error)")
        }
    }
}

private struct SettingsSnapshot: Codable {
    var pollingInterval: TimeInterval
    var defaultUsername: String
    var defaultSSHKeyPath: String
    var notificationsEnabled: Bool
    var notifyServerUnreachable: Bool
    var notifyCPUAboveThreshold: Bool
    var cpuThreshold: Double
    var notifyDiskAboveThreshold: Bool
    var diskThreshold: Double

    init(
        pollingInterval: TimeInterval,
        defaultUsername: String,
        defaultSSHKeyPath: String,
        notificationsEnabled: Bool,
        notifyServerUnreachable: Bool,
        notifyCPUAboveThreshold: Bool,
        cpuThreshold: Double,
        notifyDiskAboveThreshold: Bool,
        diskThreshold: Double
    ) {
        self.pollingInterval = pollingInterval
        self.defaultUsername = defaultUsername
        self.defaultSSHKeyPath = defaultSSHKeyPath
        self.notificationsEnabled = notificationsEnabled
        self.notifyServerUnreachable = notifyServerUnreachable
        self.notifyCPUAboveThreshold = notifyCPUAboveThreshold
        self.cpuThreshold = cpuThreshold
        self.notifyDiskAboveThreshold = notifyDiskAboveThreshold
        self.diskThreshold = diskThreshold
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pollingInterval = try container.decodeIfPresent(TimeInterval.self, forKey: .pollingInterval) ?? 5
        defaultUsername = try container.decodeIfPresent(String.self, forKey: .defaultUsername) ?? "root"
        defaultSSHKeyPath = try container.decodeIfPresent(String.self, forKey: .defaultSSHKeyPath) ?? ""
        notificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? true
        notifyServerUnreachable = try container.decodeIfPresent(Bool.self, forKey: .notifyServerUnreachable) ?? true
        notifyCPUAboveThreshold = try container.decodeIfPresent(Bool.self, forKey: .notifyCPUAboveThreshold) ?? true
        cpuThreshold = try container.decodeIfPresent(Double.self, forKey: .cpuThreshold) ?? 90
        notifyDiskAboveThreshold = try container.decodeIfPresent(Bool.self, forKey: .notifyDiskAboveThreshold) ?? true
        diskThreshold = try container.decodeIfPresent(Double.self, forKey: .diskThreshold) ?? 90
    }
}
