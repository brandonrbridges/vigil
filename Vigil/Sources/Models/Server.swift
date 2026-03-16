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
        self.host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        self.port = max(1, min(65535, port))
        self.username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        self.authMethod = authMethod
    }

    var displayName: String {
        nickname.isEmpty ? host : nickname
    }
}

enum AuthMethod: Codable, Hashable {
    case password
    case key(path: String)
}
