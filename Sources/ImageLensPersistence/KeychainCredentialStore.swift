import Foundation
import Security

public protocol CredentialStore: Sendable {
    func value(for account: String) async throws -> String?
    func setValue(_ value: String?, for account: String) async throws
}

public enum CredentialStoreError: Error, Equatable, LocalizedError, Sendable {
    case invalidEncoding
    case keychainFailure(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .invalidEncoding:
            return "凭证无法转换为 UTF-8。"
        case .keychainFailure(let status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "未知错误"
            return "macOS 钥匙串操作失败：\(message)（\(status)）"
        }
    }
}

public actor KeychainCredentialStore: CredentialStore {
    public static let defaultService = "com.jiawenqin.imagelensstudio"

    private let service: String

    public init(service: String = KeychainCredentialStore.defaultService) {
        self.service = service
    }

    public func value(for account: String) async throws -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw CredentialStoreError.keychainFailure(status)
        }
        guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw CredentialStoreError.invalidEncoding
        }
        return value
    }

    public func setValue(_ value: String?, for account: String) async throws {
        let query = baseQuery(account: account)
        guard let value, !value.isEmpty else {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw CredentialStoreError.keychainFailure(status)
            }
            return
        }
        guard let data = value.data(using: .utf8) else {
            throw CredentialStoreError.invalidEncoding
        }

        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw CredentialStoreError.keychainFailure(updateStatus)
        }

        var item = query
        item[kSecValueData as String] = data
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw CredentialStoreError.keychainFailure(addStatus)
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

public actor InMemoryCredentialStore: CredentialStore {
    private var values: [String: String] = [:]

    public init(values: [String: String] = [:]) {
        self.values = values
    }

    public func value(for account: String) async throws -> String? {
        values[account]
    }

    public func setValue(_ value: String?, for account: String) async throws {
        values[account] = value
    }
}
