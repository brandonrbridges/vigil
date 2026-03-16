import Foundation

struct VerifiedHost: Identifiable, Hashable {
    var id: String { "\(username)@\(host):\(port)" }
    let host: String
    let port: Int
    let username: String
    let keyPath: String

    func toServer() -> Server {
        Server(
            host: host,
            port: port,
            username: username,
            authMethod: .key(path: keyPath)
        )
    }
}

actor SSHProber {
    private let commonUsernames = ["root", "ubuntu", "admin", "debian", "ec2-user"]
    private let timeout: Int = 5

    /// Probe a list of hosts with all detected keys and common usernames.
    /// Returns only hosts that successfully authenticate.
    func probe(hosts: [(String, Int)]) async -> [VerifiedHost] {
        let keys = SSHKeyDetector.detectKeys()
        guard !keys.isEmpty else { return [] }

        var verified: [VerifiedHost] = []

        await withTaskGroup(of: VerifiedHost?.self) { group in
            for (host, port) in hosts {
                for key in keys {
                    for username in commonUsernames {
                        group.addTask {
                            await self.tryConnect(host: host, port: port, username: username, keyPath: key.path)
                        }
                    }
                }
            }

            // Collect first successful result per host
            var seenHosts = Set<String>()
            for await result in group {
                if let verified_host = result, !seenHosts.contains(verified_host.host) {
                    seenHosts.insert(verified_host.host)
                    verified.append(verified_host)
                }
            }
        }

        return verified
    }

    private func tryConnect(host: String, port: Int, username: String, keyPath: String) async -> VerifiedHost? {
        let process = Process()
        let pipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.standardOutput = pipe
        process.standardError = errorPipe
        process.arguments = [
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=\(timeout)",
            "-p", "\(port)",
            "-i", keyPath,
            "\(username)@\(host)",
            "echo ok"
        ]

        do {
            return try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { _ in
                    if process.terminationStatus == 0 {
                        continuation.resume(returning: VerifiedHost(
                            host: host,
                            port: port,
                            username: username,
                            keyPath: keyPath
                        ))
                    } else {
                        continuation.resume(returning: nil)
                    }
                }

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        } catch {
            return nil
        }
    }
}
