import SwiftUI

struct FilesPlaceholderView: View {
    let server: Server
    @Environment(ConnectionManager.self) private var connectionManager
    @State private var currentPath: String = "/"
    @State private var files: [RemoteFile] = []
    @State private var pathHistory: [String] = []
    @State private var isLoading = true
    @State private var selectedFileID: String?
    @State private var showInspector = false
    @State private var filePreview: String?
    @State private var showNewFolderAlert = false
    @State private var newFolderName = ""
    @State private var showDeleteConfirm = false
    @State private var searchText = ""

    private var selectedFile: RemoteFile? {
        guard let id = selectedFileID else { return nil }
        return files.first { $0.id == id }
    }

    private var sortedFiles: [RemoteFile] {
        files.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private var filteredFiles: [RemoteFile] {
        if searchText.isEmpty { return sortedFiles }
        return sortedFiles.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading files...")
            } else {
                fileTable
            }
        }
        .searchable(text: $searchText, prompt: "Filter files")
        .navigationTitle(currentPath)
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button {
                    goBack()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(pathHistory.isEmpty)

                Button {
                    goUp()
                } label: {
                    Label("Enclosing Folder", systemImage: "arrow.up")
                }
                .keyboardShortcut(.upArrow, modifiers: .command)
                .disabled(currentPath == "/")

                Button {
                    Task { await loadDirectory(currentPath) }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: .command)

                Button {
                    newFolderName = ""
                    showNewFolderAlert = true
                } label: {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Button {
                    showInspector.toggle()
                } label: {
                    Label("Inspector", systemImage: "sidebar.right")
                }
            }
        }
        .task(id: server.id) {
            guard let sftp = connectionManager.sftpService(for: server.id) else {
                isLoading = false
                return
            }
            let home = await sftp.homeDirectory()
            await loadDirectory(home)
        }
        .alert("New Folder", isPresented: $showNewFolderAlert) {
            TextField("Folder name", text: $newFolderName)
            Button("Create") {
                Task { await createFolder() }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Delete \(selectedFile?.name ?? "")?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                Task { await deleteSelected() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
    }

    private var fileTable: some View {
        Table(filteredFiles, selection: $selectedFileID) {
            TableColumn("Name") { file in
                HStack(spacing: 6) {
                    Image(systemName: file.icon)
                        .foregroundStyle(file.isDirectory ? .blue : .secondary)
                        .frame(width: 20)
                    Text(file.name)
                        .font(.callout)
                        .lineLimit(1)
                }
            }
            .width(min: 200, ideal: 350)

            TableColumn("Size") { file in
                Text(file.formattedSize)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .width(min: 70, ideal: 90)

            TableColumn("Modified") { file in
                Text(file.modified)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .width(min: 120, ideal: 150)

            TableColumn("Permissions") { file in
                Text(file.permissions)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .width(min: 100, ideal: 110)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            if let id = ids.first, let file = files.first(where: { $0.id == id }) {
                if file.isDirectory {
                    Button("Open", systemImage: "folder") {
                        navigateTo(file.path)
                    }
                } else {
                    Button("Preview", systemImage: "eye") {
                        previewFile(file)
                    }
                }

                Divider()

                Button("Delete", systemImage: "trash", role: .destructive) {
                    selectedFileID = id
                    showDeleteConfirm = true
                }
            }
        } primaryAction: { ids in
            if let id = ids.first, let file = files.first(where: { $0.id == id }) {
                if file.isDirectory {
                    navigateTo(file.path)
                } else {
                    previewFile(file)
                }
            }
        }
        .inspector(isPresented: $showInspector) {
            if let file = selectedFile {
                FileInspector(file: file, preview: filePreview)
            } else {
                ContentUnavailableView("No File Selected", systemImage: "doc", description: Text("Select a file to view its details."))
                    .inspectorColumnWidth(min: 280, ideal: 320, max: 400)
            }
        }
    }

    // MARK: - Navigation

    private func navigateTo(_ path: String) {
        pathHistory.append(currentPath)
        Task { await loadDirectory(path) }
    }

    private func goBack() {
        guard let previous = pathHistory.popLast() else { return }
        Task { await loadDirectory(previous) }
    }

    private func goUp() {
        let parent = (currentPath as NSString).deletingLastPathComponent
        pathHistory.append(currentPath)
        Task { await loadDirectory(parent) }
    }

    private func loadDirectory(_ path: String) async {
        isLoading = files.isEmpty
        guard let sftp = connectionManager.sftpService(for: server.id) else { return }
        let result = await sftp.listDirectory(path)
        currentPath = path
        files = result
        isLoading = false
        selectedFileID = nil
        filePreview = nil
    }

    // MARK: - Actions

    private func previewFile(_ file: RemoteFile) {
        guard !file.isDirectory else { return }
        showInspector = true
        selectedFileID = file.id
        Task {
            guard let sftp = connectionManager.sftpService(for: server.id) else { return }
            let content = await sftp.readFile(file.path)
            await MainActor.run {
                filePreview = content
            }
        }
    }

    private func createFolder() async {
        guard !newFolderName.isEmpty,
              let sftp = connectionManager.sftpService(for: server.id) else { return }
        let path = currentPath.hasSuffix("/") ? "\(currentPath)\(newFolderName)" : "\(currentPath)/\(newFolderName)"
        try? await sftp.mkdir(path)
        await loadDirectory(currentPath)
    }

    private func deleteSelected() async {
        guard let file = selectedFile,
              let sftp = connectionManager.sftpService(for: server.id) else { return }
        try? await sftp.delete(file.path, isDirectory: file.isDirectory)
        await loadDirectory(currentPath)
    }
}

// MARK: - Inspector

struct FileInspector: View {
    let file: RemoteFile
    let preview: String?

    var body: some View {
        Form {
            Section("Info") {
                LabeledContent("Name", value: file.name)
                LabeledContent("Path", value: file.path)
                LabeledContent("Type", value: file.isDirectory ? "Directory" : "File")
                if !file.isDirectory {
                    LabeledContent("Size", value: file.formattedSize)
                }
                LabeledContent("Modified", value: file.modified)
                LabeledContent("Permissions", value: file.permissions)
            }

            if let preview = preview {
                Section("Preview") {
                    ScrollView {
                        Text(preview.prefix(10000))
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(minHeight: 200)
                }
            }
        }
        .formStyle(.grouped)
        .inspectorColumnWidth(min: 280, ideal: 320, max: 400)
    }
}
