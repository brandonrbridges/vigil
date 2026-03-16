import SwiftUI

struct AddServerSheet: View {
    @Environment(ServerManager.self) private var serverManager
    @Environment(\.dismiss) private var dismiss
    @State private var host = ""
    @State private var port: Int = 22
    @FocusState private var isHostFocused: Bool
    @State private var username = "root"
    @State private var nickname = ""
    @State private var usePassword = false
    @State private var password = ""
    @State private var selectedKeyPath: String = ""
    @State private var detectedKeys: [URL] = []
    @State private var showKeyPicker = false

    private var isFormValid: Bool {
        guard !host.isEmpty, !username.isEmpty else { return false }
        if usePassword { return !password.isEmpty }
        return !selectedKeyPath.isEmpty
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Add Server")
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
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button("Add") {
                    let server = Server(
                        nickname: nickname,
                        host: host,
                        port: port,
                        username: username,
                        authMethod: usePassword ? .password : .key(path: selectedKeyPath)
                    )
                    Task {
                        if usePassword {
                            do {
                                try await KeychainService.shared.savePassword(password, for: server)
                            } catch {
                                print("Failed to save password to keychain: \(error)")
                            }
                        }
                        serverManager.addServer(server)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isFormValid)
            }
        }
        .padding()
        .frame(width: 400)
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
}
