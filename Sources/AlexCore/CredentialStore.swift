import Foundation
import Security
import LocalAuthentication

public struct CredentialStore: Sendable {
    private let service: String
    public init(service: String) { self.service = service }
    private var query: [String: Any] {
        let context = LAContext()
        context.interactionNotAllowed = true
        return [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                kSecAttrAccount as String: "api-key", kSecUseAuthenticationContext as String: context]
    }
    public func read() throws -> String? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        try check(status)
        guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw KeychainFailure(status: errSecDecode)
        }
        return value
    }
    public func save(_ value: String) throws {
        if value.isEmpty { try delete(); return }
        let data = Data(value.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status != errSecItemNotFound { try check(status); return }
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        try check(SecItemAdd(item as CFDictionary, nil))
    }
    public func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }
    private func check(_ status: OSStatus) throws {
        if status != errSecSuccess { throw KeychainFailure(status: status) }
    }
}

public struct KeychainFailure: LocalizedError, Sendable {
    public let status: OSStatus
    public var errorDescription: String? { "无法访问钥匙串（\(status)）。请解锁登录钥匙串后重试，密钥尚未保存。" }
}
