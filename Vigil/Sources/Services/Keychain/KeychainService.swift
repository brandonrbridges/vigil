import Foundation
import Security

actor KeychainService {
    static let shared = KeychainService()

    private let serviceIdentifier = "com.vigil.server-monitor"

    func savePassword(_ password: String, for server: Server) throws {
        let account = "\(server.username)@\(server.host):\(server.port)"
        let data = Data(password.utf8)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]

        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    func loadPassword(for server: Server) throws -> String? {
        let account = "\(server.username)@\(server.host):\(server.port)"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            if status == errSecItemNotFound { return nil }
            throw KeychainError.loadFailed(status)
        }

        return String(data: data, encoding: .utf8)
    }

    func deletePassword(for server: Server) throws {
        let account = "\(server.username)@\(server.host):\(server.port)"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }
}

enum KeychainError: Error, LocalizedError {
    case saveFailed(OSStatus)
    case loadFailed(OSStatus)
    case deleteFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .saveFailed(let status): "Failed to save to Keychain (status: \(status))"
        case .loadFailed(let status): "Failed to load from Keychain (status: \(status))"
        case .deleteFailed(let status): "Failed to delete from Keychain (status: \(status))"
        }
    }
}
