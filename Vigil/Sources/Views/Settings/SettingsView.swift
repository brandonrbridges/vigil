import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            NotificationSettingsTab()
                .tabItem {
                    Label("Notifications", systemImage: "bell")
                }

            AboutSettingsTab()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 450, height: 350)
    }
}

// MARK: - General Tab

private struct GeneralSettingsTab: View {
    @Environment(AppSettings.self) private var settings

    private let pollingIntervals: [(String, TimeInterval)] = [
        ("3 seconds", 3),
        ("5 seconds", 5),
        ("10 seconds", 10),
        ("30 seconds", 30),
    ]

    var body: some View {
        @Bindable var settings = settings

        Form {
            Picker("Polling interval:", selection: $settings.pollingInterval) {
                ForEach(pollingIntervals, id: \.1) { label, value in
                    Text(label).tag(value)
                }
            }

            TextField("Default username:", text: $settings.defaultUsername)
                .textFieldStyle(.roundedBorder)

            Picker("Default SSH key:", selection: $settings.defaultSSHKeyPath) {
                Text("None").tag("")
                ForEach(SSHKeyDetector.detectKeys(), id: \.path) { keyURL in
                    Text(keyURL.lastPathComponent).tag(keyURL.path)
                }
            }

            Toggle("Launch at login", isOn: $settings.launchAtLogin)
        }
        .formStyle(.grouped)
        .onChange(of: settings.pollingInterval) { _, _ in settings.save() }
        .onChange(of: settings.defaultUsername) { _, _ in settings.save() }
        .onChange(of: settings.defaultSSHKeyPath) { _, _ in settings.save() }
        .onChange(of: settings.launchAtLogin) { _, _ in settings.save() }
    }
}

// MARK: - Notifications Tab

private struct NotificationSettingsTab: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Form {
            Toggle("Enable notifications", isOn: $settings.notificationsEnabled)

            Section {
                Toggle("Server unreachable", isOn: $settings.notifyServerUnreachable)

                Toggle("CPU above threshold", isOn: $settings.notifyCPUAboveThreshold)
                if settings.notifyCPUAboveThreshold {
                    HStack {
                        Slider(value: $settings.cpuThreshold, in: 50...100, step: 5)
                        Text("\(Int(settings.cpuThreshold))%")
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }

                Toggle("Disk above threshold", isOn: $settings.notifyDiskAboveThreshold)
                if settings.notifyDiskAboveThreshold {
                    HStack {
                        Slider(value: $settings.diskThreshold, in: 50...100, step: 5)
                        Text("\(Int(settings.diskThreshold))%")
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }

                Toggle("Container stopped", isOn: $settings.notifyContainerStopped)
            }
            .disabled(!settings.notificationsEnabled)
        }
        .formStyle(.grouped)
        .onChange(of: settings.notificationsEnabled) { _, _ in settings.save() }
        .onChange(of: settings.notifyServerUnreachable) { _, _ in settings.save() }
        .onChange(of: settings.notifyCPUAboveThreshold) { _, _ in settings.save() }
        .onChange(of: settings.cpuThreshold) { _, _ in settings.save() }
        .onChange(of: settings.notifyDiskAboveThreshold) { _, _ in settings.save() }
        .onChange(of: settings.diskThreshold) { _, _ in settings.save() }
        .onChange(of: settings.notifyContainerStopped) { _, _ in settings.save() }
    }
}

// MARK: - About Tab

private struct AboutSettingsTab: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "server.rack")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Vigil")
                .font(.title)
                .fontWeight(.bold)

            Text("Version 1.0.0")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("Native macOS Server Monitor")
                .font(.body)

            Text("100% local. No telemetry. MIT licensed.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Text("https://github.com/yourusername/vigil")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
