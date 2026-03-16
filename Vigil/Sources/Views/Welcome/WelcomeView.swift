import SwiftUI

struct WelcomeView: View {
    @Environment(ServerManager.self) private var serverManager
    @Environment(ConnectionManager.self) private var connectionManager
    @State private var host = ""
    @State private var port: Int = 22
    @FocusState private var isHostFocused: Bool
    @State private var username = "root"
    @State private var nickname = ""
    @State private var authMethod: AuthMethodSelection = .key
    @State private var password = ""
    @State private var selectedKeyPath: String = ""
    @State private var detectedKeys: [URL] = []
    @State private var isConnecting = false
    @State private var errorMessage: String?
    @State private var showKeyPicker = false

    enum AuthMethodSelection: String, CaseIterable {
        case password = "Password"
        case key = "SSH Key"
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                headerSection
                formSection
                connectButton
            }
            .padding(40)
            .frame(maxWidth: 480)
            .glassEffect(.regular, in: .rect(cornerRadius: 24))

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            detectedKeys = SSHKeyDetector.detectKeys()
            selectedKeyPath = SSHKeyDetector.defaultKey?.path ?? ""
            isHostFocused = true
        }
        .fileImporter(
            isPresented: $showKeyPicker,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                selectedKeyPath = url.path
                if !detectedKeys.contains(where: { $0.path == url.path }) {
                    detectedKeys.append(url)
                }
            }
        }
    }

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "server.rack")
                .font(.system(size: 48))
                .foregroundStyle(.tint)

            Text("Vigil")
                .font(.title.bold())

            Text("Connect to your server to get started")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var formSection: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                LabeledContent("Host") {
                    TextField("192.168.1.1", text: $host)
                        .textFieldStyle(.roundedBorder)
                        .focused($isHostFocused)
                }

                LabeledContent("Port") {
                    TextField("Port", value: $port, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                }
            }

            LabeledContent("Username") {
                TextField("root", text: $username)
                    .textFieldStyle(.roundedBorder)
            }

            LabeledContent("Nickname") {
                TextField("My Server (optional)", text: $nickname)
                    .textFieldStyle(.roundedBorder)
            }

            Picker("Auth", selection: $authMethod) {
                ForEach(AuthMethodSelection.allCases, id: \.self) { method in
                    Text(method.rawValue).tag(method)
                }
            }
            .pickerStyle(.segmented)

            switch authMethod {
            case .password:
                LabeledContent("Password") {
                    SecureField("Password", text: $password)
                        .textFieldStyle(.roundedBorder)
                }
            case .key:
                LabeledContent("Key") {
                    HStack(spacing: 8) {
                        if detectedKeys.isEmpty {
                            Text("No keys auto-detected")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Picker("SSH Key", selection: $selectedKeyPath) {
                                ForEach(detectedKeys, id: \.path) { key in
                                    Text(key.lastPathComponent).tag(key.path)
                                }
                            }
                        }

                        Button("Browse...") {
                            showKeyPicker = true
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var isFormValid: Bool {
        guard !host.isEmpty, !username.isEmpty else { return false }
        switch authMethod {
        case .password:
            return !password.isEmpty
        case .key:
            return !selectedKeyPath.isEmpty
        }
    }

    private var connectButton: some View {
        Button {
            connectToServer()
        } label: {
            HStack(spacing: 8) {
                if isConnecting {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(isConnecting ? "Verifying connection..." : "Connect")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!isFormValid || isConnecting)
    }

    private func connectToServer() {
        errorMessage = nil
        isConnecting = true

        let auth: AuthMethod = switch authMethod {
        case .password: .password
        case .key: .key(path: selectedKeyPath)
        }

        let server = Server(
            nickname: nickname,
            host: host,
            port: port,
            username: username,
            authMethod: auth
        )

        Task {
            do {
                // Verify we can actually connect
                try await connectionManager.testConnection(for: server)

                // Save password if using password auth
                if case .password = authMethod {
                    try? await KeychainService.shared.savePassword(password, for: server)
                }

                // Add server and start monitoring
                await MainActor.run {
                    serverManager.addServer(server)
                }
                await connectionManager.connect(to: server)

                await MainActor.run {
                    isConnecting = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isConnecting = false
                }
            }
        }
    }
}
