import Foundation

struct SSHConfigEntry: Identifiable, Hashable {
    var id: String { "\(user)@\(hostname):\(port)" }
    let alias: String
    let hostname: String
    let user: String
    let port: Int
    let identityFile: String

    func toServer() -> Server {
        Server(
            nickname: alias == hostname ? "" : alias,
            host: hostname,
            port: port,
            username: user,
            authMethod: identityFile.isEmpty ? .key(path: SSHKeyDetector.defaultKey?.path ?? "") : .key(path: identityFile)
        )
    }
}

struct SSHConfigParser {
    /// Parse both ~/.ssh/config and ~/.ssh/known_hosts for discoverable servers
    static func parse() -> [SSHConfigEntry] {
        var entries = parseConfig()
        let knownEntries = parseKnownHosts()

        // Add known_hosts entries that aren't already in config
        let configHosts = Set(entries.map(\.hostname))
        for entry in knownEntries where !configHosts.contains(entry.hostname) {
            entries.append(entry)
        }

        return entries
    }

    // MARK: - SSH Config

    private static func parseConfig() -> [SSHConfigEntry] {
        let configPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ssh/config")

        guard let contents = try? String(contentsOf: configPath, encoding: .utf8) else {
            return []
        }

        var entries: [SSHConfigEntry] = []
        var currentAlias: String?
        var hostname: String?
        var user: String?
        var port: Int?
        var identityFile: String?

        func commitEntry() {
            if let alias = currentAlias, let host = hostname {
                guard !alias.contains("*") else { return }
                entries.append(SSHConfigEntry(
                    alias: alias,
                    hostname: host,
                    user: user ?? "root",
                    port: port ?? 22,
                    identityFile: resolveHome(identityFile ?? "")
                ))
            }
        }

        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }

            let parts = trimmed.split(separator: " ", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }

            let key = parts[0].lowercased()
            let value = parts[1].trimmingCharacters(in: .whitespaces)

            switch key {
            case "host":
                commitEntry()
                currentAlias = value
                hostname = nil
                user = nil
                port = nil
                identityFile = nil
            case "hostname":
                hostname = value
            case "user":
                user = value
            case "port":
                port = Int(value)
            case "identityfile":
                identityFile = value
            default:
                break
            }
        }
        commitEntry()

        return entries
    }

    // MARK: - Known Hosts

    private static func parseKnownHosts() -> [SSHConfigEntry] {
        let knownHostsPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ssh/known_hosts")

        guard let contents = try? String(contentsOf: knownHostsPath, encoding: .utf8) else {
            return []
        }

        var seen = Set<String>()
        var entries: [SSHConfigEntry] = []
        let defaultKey = SSHKeyDetector.defaultKey?.path ?? ""

        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }

            let parts = trimmed.split(separator: " ", maxSplits: 2)
            guard parts.count >= 2 else { continue }

            var host = String(parts[0])
            var port = 22

            // Skip hashed known_hosts entries
            guard !host.hasPrefix("|") else { continue }

            // Handle [host]:port format
            if host.hasPrefix("["), let closeBracket = host.firstIndex(of: "]") {
                let hostPart = String(host[host.index(after: host.startIndex)..<closeBracket])
                let afterBracket = String(host[host.index(after: closeBracket)...])
                if afterBracket.hasPrefix(":"), let p = Int(afterBracket.dropFirst()) {
                    port = p
                }
                host = hostPart
            }

            // Skip non-IP/hostname entries (like github.com, gitlab.com, localhost.run)
            let isIPv4 = host.range(of: #"^\d+\.\d+\.\d+\.\d+$"#, options: .regularExpression) != nil
            guard isIPv4 else { continue }

            // Deduplicate — known_hosts often has multiple key types per host
            guard !seen.contains(host) else { continue }
            seen.insert(host)

            entries.append(SSHConfigEntry(
                alias: host,
                hostname: host,
                user: "root",
                port: port,
                identityFile: defaultKey
            ))
        }

        return entries
    }

    private static func resolveHome(_ path: String) -> String {
        if path.hasPrefix("~") {
            return path.replacingOccurrences(
                of: "~",
                with: FileManager.default.homeDirectoryForCurrentUser.path,
                options: .anchored
            )
        }
        return path
    }
}
