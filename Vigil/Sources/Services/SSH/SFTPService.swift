import Foundation

enum SFTPError: LocalizedError {
    case fileTooLarge(Int64)
    case transferFailed(String)

    var errorDescription: String? {
        switch self {
        case .fileTooLarge(let size):
            let mb = size / (1024 * 1024)
            return "File is too large (\(mb) MB). Maximum transfer size is 50 MB."
        case .transferFailed(let reason):
            return "Transfer failed: \(reason)"
        }
    }
}

actor SFTPService {
    let connection: SSHConnection
    private let maxTransferSize: Int64 = 50 * 1024 * 1024

    init(connection: SSHConnection) {
        self.connection = connection
    }

    /// List files in a directory
    func listDirectory(_ path: String) async -> [RemoteFile] {
        // Use ls -la with a parseable format
        guard let output = try? await connection.execute(
            "ls -la --time-style=long-iso \(shellEscape(path)) 2>/dev/null"
        ) else {
            return []
        }

        let lines = output.split(separator: "\n").dropFirst() // skip "total" line
        return lines.compactMap { line in
            parseLsLine(String(line), parentPath: path)
        }
    }

    /// Read a text file's contents (limited to 32 KB for preview)
    func readFile(_ path: String) async -> String? {
        try? await connection.execute("head -c 32768 \(shellEscape(path)) 2>/dev/null")
    }

    /// Get the size of a remote file in bytes
    func fileSize(_ path: String) async -> Int64? {
        guard let output = try? await connection.execute("stat -c %s \(shellEscape(path)) 2>/dev/null") else {
            return nil
        }
        return Int64(output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Delete a file or directory
    func delete(_ path: String, isDirectory: Bool) async throws {
        let cmd = isDirectory ? "rm -rf" : "rm -f"
        _ = try await connection.execute("\(cmd) \(shellEscape(path))")
    }

    /// Create a directory
    func mkdir(_ path: String) async throws {
        _ = try await connection.execute("mkdir -p \(shellEscape(path))")
    }

    /// Get the home directory
    func homeDirectory() async -> String {
        let result = (try? await connection.execute("echo $HOME")) ?? "/root"
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Download a file to a local path using base64 encoding
    func downloadFile(remotePath: String, localURL: URL) async throws {
        if let size = await fileSize(remotePath), size > maxTransferSize {
            throw SFTPError.fileTooLarge(size)
        }
        guard let output = try? await connection.execute("base64 \(shellEscape(remotePath))") else {
            throw SFTPError.transferFailed("Failed to read remote file.")
        }
        guard let data = Data(base64Encoded: output.trimmingCharacters(in: .whitespacesAndNewlines), options: .ignoreUnknownCharacters) else {
            throw SFTPError.transferFailed("Failed to decode file data.")
        }
        do {
            try data.write(to: localURL)
        } catch {
            throw SFTPError.transferFailed(error.localizedDescription)
        }
    }

    /// Upload a local file to the server using base64 encoding
    func uploadFile(localURL: URL, remotePath: String) async throws {
        let attrs = try? FileManager.default.attributesOfItem(atPath: localURL.path)
        if let fileSize = attrs?[.size] as? Int64, fileSize > maxTransferSize {
            throw SFTPError.fileTooLarge(fileSize)
        }
        guard let data = try? Data(contentsOf: localURL) else {
            throw SFTPError.transferFailed("Failed to read local file.")
        }
        let base64 = data.base64EncodedString()
        let command = "echo '\(base64)' | base64 -d > \(shellEscape(remotePath))"
        guard (try? await connection.execute(command)) != nil else {
            throw SFTPError.transferFailed("Failed to write remote file.")
        }
    }

    // MARK: - Parsing

    private func parseLsLine(_ line: String, parentPath: String) -> RemoteFile? {
        // Format: drwxr-xr-x 2 user group 4096 2024-01-15 10:30 filename
        let parts = line.split(separator: " ", maxSplits: 7, omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 8 else { return nil }

        let permissions = parts[0]
        let size = Int64(parts[4]) ?? 0
        let modified = "\(parts[5]) \(parts[6])"
        let name = parts[7]

        // Skip . and ..
        guard name != "." && name != ".." else { return nil }

        let isDirectory = permissions.hasPrefix("d")
        let path = parentPath.hasSuffix("/") ? "\(parentPath)\(name)" : "\(parentPath)/\(name)"

        return RemoteFile(
            name: name,
            path: path,
            isDirectory: isDirectory,
            size: size,
            modified: modified,
            permissions: String(permissions)
        )
    }

    private func shellEscape(_ path: String) -> String {
        let sanitized = path.replacingOccurrences(of: "\0", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
        return "'" + sanitized.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
