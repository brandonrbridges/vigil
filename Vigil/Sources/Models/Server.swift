import Foundation

struct Server: Identifiable, Codable, Hashable {
    let id: UUID
    var nickname: String
    var host: String
    var port: Int
    var username: String
    var authMethod: AuthMethod

    init(
        id: UUID = UUID(),
        nickname: String = "",
        host: String,
        port: Int = 22,
        username: String = "root",
        authMethod: AuthMethod = .key(path: "")
    ) {
        self.id = id
        self.nickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        self.host = Self.sanitizeHostname(host.trimmingCharacters(in: .whitespacesAndNewlines))
        self.port = max(1, min(65535, port))
        self.username = Self.sanitizeUsername(username.trimmingCharacters(in: .whitespacesAndNewlines))
        self.authMethod = authMethod
    }

    /// Strips characters not matching `[a-zA-Z0-9._-]` from a hostname string.
    static func sanitizeHostname(_ input: String) -> String {
        String(input.unicodeScalars.filter { scalar in
            CharacterSet.alphanumerics.contains(scalar)
                || scalar == "."
                || scalar == "_"
                || scalar == "-"
        })
    }

    /// Strips characters not matching `[a-zA-Z0-9._-]` from a username string.
    private static func sanitizeUsername(_ input: String) -> String {
        String(input.unicodeScalars.filter { scalar in
            CharacterSet.alphanumerics.contains(scalar)
                || scalar == "."
                || scalar == "_"
                || scalar == "-"
        })
    }

    var displayName: String {
        nickname.isEmpty ? host : nickname
    }
}

enum AuthMethod: Codable, Hashable {
    case password
    case key(path: String)
}
