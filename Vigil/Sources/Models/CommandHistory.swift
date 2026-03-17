import Foundation
import SwiftUI

@MainActor @Observable
final class CommandHistoryManager {
    var history: [CommandEntry] = []
    var favourites: [CommandEntry] = []
    var quickInsertEnabled: Bool = true
    var hasAskedAboutQuickInsert: Bool = false

    private let storageURL: URL
    private var saveTask: Task<Void, Never>?

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Vigil", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        storageURL = appSupport.appendingPathComponent("command-history.json")
        load()
    }

    func recordCommand(_ command: String, serverID: UUID) {
        // Don't record empty or duplicate consecutive commands
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let last = history.last(where: { $0.serverID == serverID }), last.command == trimmed { return }

        let entry = CommandEntry(command: trimmed, serverID: serverID, timestamp: .now)
        history.append(entry)

        // Keep last 500
        if history.count > 500 {
            history.removeFirst(history.count - 500)
        }
        scheduleSave()
    }

    func toggleFavourite(_ entry: CommandEntry) {
        if let idx = favourites.firstIndex(where: { $0.command == entry.command }) {
            favourites.remove(at: idx)
        } else {
            favourites.append(entry)
        }
        performSave()
    }

    func isFavourite(_ command: String) -> Bool {
        favourites.contains { $0.command == command }
    }

    func clearHistory() {
        history.removeAll()
        performSave()
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let stored = try? JSONDecoder().decode(StoredHistory.self, from: data) else { return }
        history = stored.history
        favourites = stored.favourites
        quickInsertEnabled = stored.quickInsertEnabled
        hasAskedAboutQuickInsert = stored.hasAskedAboutQuickInsert
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            performSave()
        }
    }

    private func performSave() {
        let stored = StoredHistory(
            history: history,
            favourites: favourites,
            quickInsertEnabled: quickInsertEnabled,
            hasAskedAboutQuickInsert: hasAskedAboutQuickInsert
        )
        if let data = try? JSONEncoder().encode(stored) {
            try? data.write(to: storageURL, options: .atomic)
        }
    }
}

struct CommandEntry: Identifiable, Codable, Hashable {
    let id: UUID
    let command: String
    let serverID: UUID
    let timestamp: Date

    init(id: UUID = UUID(), command: String, serverID: UUID, timestamp: Date = .now) {
        self.id = id
        self.command = command
        self.serverID = serverID
        self.timestamp = timestamp
    }
}

private struct StoredHistory: Codable {
    var history: [CommandEntry]
    var favourites: [CommandEntry]
    var quickInsertEnabled: Bool
    var hasAskedAboutQuickInsert: Bool

    enum CodingKeys: String, CodingKey {
        case history, favourites, quickInsertEnabled, hasAskedAboutQuickInsert
    }

    init(history: [CommandEntry], favourites: [CommandEntry], quickInsertEnabled: Bool, hasAskedAboutQuickInsert: Bool) {
        self.history = history
        self.favourites = favourites
        self.quickInsertEnabled = quickInsertEnabled
        self.hasAskedAboutQuickInsert = hasAskedAboutQuickInsert
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        history = try container.decode([CommandEntry].self, forKey: .history)
        favourites = try container.decode([CommandEntry].self, forKey: .favourites)
        quickInsertEnabled = try container.decodeIfPresent(Bool.self, forKey: .quickInsertEnabled) ?? true
        hasAskedAboutQuickInsert = try container.decodeIfPresent(Bool.self, forKey: .hasAskedAboutQuickInsert) ?? false
    }
}
