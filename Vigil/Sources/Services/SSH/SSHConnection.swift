import Foundation

actor SSHConnection {
    let server: Server
    init(server: Server) {
        self.server = server
    }

    /// Test the connection by running a simple command
    func testConnection() async throws {
        let result = try await execute("echo connected")
        guard result.trimmingCharacters(in: .whitespacesAndNewlines) == "connected" else {
            throw SSHError.connectionFailed("Unexpected response: \(result)")
        }
    }

    /// Execute a command on the remote server via SSH
    func execute(_ command: String) async throws -> String {
        guard FileManager.default.fileExists(atPath: "/usr/bin/ssh") else {
            throw SSHError.launchFailed("SSH client not found at /usr/bin/ssh")
        }

        let process = Process()
        let pipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.standardOutput = pipe
        process.standardError = errorPipe

        var args: [String] = []
        args.append("-o"); args.append("StrictHostKeyChecking=accept-new")
        args.append("-o"); args.append("ControlMaster=auto")
        args.append("-o"); args.append("ControlPath=/tmp/ssm-%r@%h:%p")
        args.append("-o"); args.append("ControlPersist=60")
        args.append("-o"); args.append("ConnectTimeout=10")
        args.append("-o"); args.append("BatchMode=yes")
        args.append("-p"); args.append("\(server.port)")

        switch server.authMethod {
        case .key(let path):
            if !path.isEmpty {
                args.append("-i"); args.append(path)
            }
        case .password:
            throw SSHError.passwordNotSupported
        }

        let host = server.host.trimmingCharacters(in: .whitespacesAndNewlines)
        let username = server.username.trimmingCharacters(in: .whitespacesAndNewlines)
        args.append("\(username)@\(host)")
        args.append(command)

        process.arguments = args

        return try await withCheckedThrowingContinuation { continuation in
            // Read both pipes concurrently via readabilityHandler to avoid deadlock
            let stdoutData = LockedData()
            let stderrData = LockedData()

            pipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if !chunk.isEmpty {
                    stdoutData.append(chunk)
                }
            }
            errorPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if !chunk.isEmpty {
                    stderrData.append(chunk)
                }
            }

            process.terminationHandler = { _ in
                pipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil
                // Read any remaining data after handlers are removed
                stdoutData.append(pipe.fileHandleForReading.readDataToEndOfFile())
                stderrData.append(errorPipe.fileHandleForReading.readDataToEndOfFile())

                if process.terminationStatus == 0 {
                    let output = String(data: stdoutData.read(), encoding: .utf8) ?? ""
                    continuation.resume(returning: output)
                } else {
                    let errorOutput = String(data: stderrData.read(), encoding: .utf8) ?? "Unknown error"
                    continuation.resume(throwing: SSHError.commandFailed(
                        exitCode: Int(process.terminationStatus),
                        message: errorOutput
                    ))
                }
            }

            do {
                try process.run()
            } catch {
                pipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(throwing: SSHError.launchFailed(error.localizedDescription))
            }
        }
    }
}

/// Thread-safe Data accumulator for concurrent pipe reading.
private final class LockedData: @unchecked Sendable {
    private var data = Data()
    private let lock = NSLock()

    func append(_ chunk: Data) {
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    func read() -> Data {
        lock.lock()
        let copy = data
        lock.unlock()
        return copy
    }
}

enum SSHError: Error, LocalizedError {
    case connectionFailed(String)
    case commandFailed(exitCode: Int, message: String)
    case launchFailed(String)
    case passwordNotSupported

    var errorDescription: String? {
        switch self {
        case .connectionFailed(let msg): "Connection failed: \(msg)"
        case .commandFailed(_, let msg): msg.trimmingCharacters(in: .whitespacesAndNewlines)
        case .launchFailed(let msg): "Failed to launch SSH: \(msg)"
        case .passwordNotSupported: "Password authentication is not yet supported. Please use SSH key authentication."
        }
    }
}
