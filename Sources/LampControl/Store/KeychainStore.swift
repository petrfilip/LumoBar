import Foundation
import Security

final class KeychainStore {
    private let defaultService = "LampControl.Tuya"
    private let defaultAccount = "tuya-access-secret"

    func readSecret() throws -> String {
        try readSecret(service: defaultService, account: defaultAccount)
    }

    func saveSecret(_ secret: String) throws {
        try saveSecret(secret, service: defaultService, account: defaultAccount)
    }

    func readSecret(service: String, account: String) throws -> String {
        var query = baseQuery(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return ""
        }

        guard status == errSecSuccess else {
            throw LampControlError.keychain(String(format: NSLocalizedString("error.keychain.read", comment: ""), status))
        }

        guard let data = result as? Data, let secret = String(data: data, encoding: .utf8) else {
            throw LampControlError.keychain(NSLocalizedString("error.keychain.unreadable", comment: ""))
        }

        return secret
    }

    func saveSecret(_ secret: String, service: String, account: String) throws {
        let data = Data(secret.utf8)
        var query = baseQuery(service: service, account: account)
        let attributes = [kSecValueData as String: data]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }

        if updateStatus != errSecItemNotFound {
            throw LampControlError.keychain(String(format: NSLocalizedString("error.keychain.update", comment: ""), updateStatus))
        }

        query[kSecValueData as String] = data
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw LampControlError.keychain(String(format: NSLocalizedString("error.keychain.save", comment: ""), addStatus))
        }
    }

    private func baseQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
