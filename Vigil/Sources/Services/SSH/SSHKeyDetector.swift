import Foundation

struct SSHKeyDetector {
    static let commonKeyNames = ["id_ed25519", "id_rsa", "id_ecdsa"]

    static func detectKeys() -> [URL] {
        let sshDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ssh", isDirectory: true)

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: sshDir,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }

        return contents.filter { url in
            let name = url.lastPathComponent
            return commonKeyNames.contains(name) && !name.hasSuffix(".pub")
        }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static var defaultKey: URL? {
        detectKeys().first
    }
}
