import Foundation
import UserNotifications

@MainActor
final class NotificationService {
    private var firedAlerts: [UUID: Set<String>] = [:]
    private var failureCounts: [UUID: Int] = [:]

    let settings: AppSettings

    // Notification category identifiers
    private enum Category {
        static let serverDown = "serverDown"
        static let cpuHigh = "cpuHigh"
        static let diskHigh = "diskHigh"
        static let containerStopped = "containerStopped"
    }

    init(settings: AppSettings) {
        self.settings = settings
        registerCategories()
    }

    // MARK: - Permission

    func requestPermission() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error {
                print("Notification permission error: \(error)")
            }
        }
    }

    // MARK: - Alert Dispatch

    func sendAlert(title: String, body: String, serverName: String, categoryIdentifier: String = "") {
        guard settings.notificationsEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if !categoryIdentifier.isEmpty {
            content.categoryIdentifier = categoryIdentifier
        }
        content.userInfo = ["serverName": serverName]

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("Failed to deliver notification: \(error)")
            }
        }
    }

    // MARK: - Threshold Checking

    func checkAndNotify(
        serverID: UUID,
        serverName: String,
        metrics: ServerMetrics,
        state: ConnectionManager.ConnectionState
    ) {
        guard settings.notificationsEnabled else { return }

        var alerts = firedAlerts[serverID] ?? []

        // --- CPU threshold ---
        if settings.notifyCPUAboveThreshold {
            if metrics.cpu.usagePercent >= settings.cpuThreshold {
                if !alerts.contains(Category.cpuHigh) {
                    alerts.insert(Category.cpuHigh)
                    sendAlert(
                        title: "High CPU Usage",
                        body: "\(serverName) CPU at \(Int(metrics.cpu.usagePercent))%",
                        serverName: serverName,
                        categoryIdentifier: Category.cpuHigh
                    )
                }
            } else {
                alerts.remove(Category.cpuHigh)
            }
        }

        // --- Disk threshold ---
        if settings.notifyDiskAboveThreshold {
            let maxDiskUsage = metrics.disk.map(\.usagePercent).max() ?? 0
            if maxDiskUsage >= settings.diskThreshold {
                if !alerts.contains(Category.diskHigh) {
                    alerts.insert(Category.diskHigh)
                    sendAlert(
                        title: "High Disk Usage",
                        body: "\(serverName) disk at \(Int(maxDiskUsage))%",
                        serverName: serverName,
                        categoryIdentifier: Category.diskHigh
                    )
                }
            } else {
                alerts.remove(Category.diskHigh)
            }
        }

        firedAlerts[serverID] = alerts
    }

    /// Record a poll failure for a server. Sends a notification after 3 consecutive failures.
    func recordPollFailure(serverID: UUID, serverName: String) {
        guard settings.notificationsEnabled, settings.notifyServerUnreachable else { return }

        let count = (failureCounts[serverID] ?? 0) + 1
        failureCounts[serverID] = count

        if count == 3 {
            var alerts = firedAlerts[serverID] ?? []
            if !alerts.contains(Category.serverDown) {
                alerts.insert(Category.serverDown)
                firedAlerts[serverID] = alerts
                sendAlert(
                    title: "Server Unreachable",
                    body: "\(serverName) has failed to respond 3 times in a row",
                    serverName: serverName,
                    categoryIdentifier: Category.serverDown
                )
            }
        }
    }

    /// Reset failure count on successful poll.
    func recordPollSuccess(serverID: UUID) {
        failureCounts[serverID] = 0
        firedAlerts[serverID]?.remove(Category.serverDown)
    }

    /// Clear all tracked state for a server (e.g. on disconnect).
    func clearState(for serverID: UUID) {
        firedAlerts.removeValue(forKey: serverID)
        failureCounts.removeValue(forKey: serverID)
    }

    // MARK: - Private

    private func registerCategories() {
        let categories: Set<UNNotificationCategory> = [
            UNNotificationCategory(identifier: Category.serverDown, actions: [], intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.cpuHigh, actions: [], intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.diskHigh, actions: [], intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.containerStopped, actions: [], intentIdentifiers: []),
        ]
        UNUserNotificationCenter.current().setNotificationCategories(categories)
    }
}
