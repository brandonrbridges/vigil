import SwiftUI

struct EditServerSheet: View {
    @Environment(ServerManager.self) private var serverManager
    @Environment(ConnectionManager.self) private var connectionManager
    @Environment(\.dismiss) private var dismiss

    let server: Server

    @State private var host: String
    @State private var port: Int
    @FocusState private var isHostFocused: Bool
    @State private var username: String
    @State private var nickname: String
    @State private var usePassword: Bool
    @State private var password: String = ""
    @State private var selectedKeyPath: String
    @State private var detectedKeys: [URL] = []
    @State private var showKeyPicker = false
    @State private var isTesting = false
    @State private var isSaving = false
    @State private var testResult: TestResult?

    enum TestResult {
        case success
        case failure(String)
    }

    init(server: Server) {
        self.server = server
        _host = State(initialValue: server.host)
        _port = State(initialValue: server.port)
        _username = State(initialValue: server.username)
        _nickname = State(initialValue: server.nickname)

        switch server.authMethod {
        case .password:
            _usePassword = State(initialValue: true)
            _selectedKeyPath = State(initialValue: "")
        case .key(let path):
            _usePassword = State(initialValue: false)
            _selectedKeyPath = State(initialValue: path)
        }
    }

    private var isFormValid: Bool {
        guard !host.isEmpty, !username.isEmpty else { return false }
        if usePassword { return !password.isEmpty }
        return !selectedKeyPath.isEmpty
    }

    private var editedServer: Server {
        Server(
            id: server.id,
            nickname: nickname,
            host: host,
            port: port,
            username: username,
            authMethod: usePassword ? .password : .key(path: selectedKeyPath)
        )
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Edit Server")
                .font(.title2.bold())

            Form {
                TextField("Host", text: $host)
                    .focused($isHostFocused)
                TextField("Port", value: $port, format: .number)
                TextField("Username", text: $username)
                TextField("Nickname (optional)", text: $nickname)

                Picker("Authentication", selection: $usePassword) {
                    Text("SSH Key").tag(false)
                    Text("Password").tag(true)
                }

                if usePassword {
                    SecureField("Password", text: $password)
                } else {
                    if !detectedKeys.isEmpty {
                        Picker("Key", selection: $selectedKeyPath) {
                            ForEach(detectedKeys, id: \.path) { key in
                                Text(key.lastPathComponent).tag(key.path)
                            }
                        }
                    }
                    Button("Browse for Key...") {
                        showKeyPicker = true
                    }
                }

                if let testResult {
                    switch testResult {
                    case .success:
                        Label("Connection successful", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    case .failure(let message):
                        Label(message, systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Test Connection") {
                    testConnection()
                }
                .disabled(!isFormValid || isTesting)

                Spacer()

                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button("Save") {
                    Task { await save() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isFormValid || isSaving)
            }
        }
        .padding()
        .frame(width: 440)
        .onAppear {
            detectedKeys = SSHKeyDetector.detectKeys()
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

    private func testConnection() {
        isTesting = true
        testResult = nil

        Task { @MainActor in
            do {
                try await connectionManager.testConnection(for: editedServer)
                testResult = .success
                isTesting = false
            } catch {
                testResult = .failure(error.localizedDescription)
                isTesting = false
            }
        }
    }

    private func save() async {
        isSaving = true
        let updated = editedServer

        if usePassword && !password.isEmpty {
            try? await KeychainService.shared.savePassword(password, for: updated)
        }

        // Disconnect old connection, update server, reconnect
        await connectionManager.disconnect(from: server)
        serverManager.updateServer(updated)

        // Fire-and-forget reconnect — connection state is shown in sidebar
        Task { await connectionManager.connect(to: updated) }

        dismiss()
    }
}
